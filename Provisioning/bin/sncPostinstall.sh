#!/bin/bash

set -exuo pipefail

export LC_ALL=C
export LANG=C

OKD_REGISTRY=${OKD_REGISTRY:-registry.svc.ci.openshift.org/origin/release}

CRC_PV_DIR="/mnt/pv-data"
SSH="ssh"

function create_json_description {
    openshiftInstallerVersion=$(${OPENSHIFT_INSTALL} version)
    sncGitHash=$(git describe --abbrev=4 HEAD 2>/dev/null || git rev-parse --short=4 HEAD)
    echo {} | ${JQ} '.version = "1.0"' \
            | ${JQ} '.type = "snc"' \
            | ${JQ} ".buildInfo.buildTime = \"$(date -u --iso-8601=seconds)\"" \
            | ${JQ} ".buildInfo.openshiftInstallerVersion = \"${openshiftInstallerVersion}\"" \
            | ${JQ} ".buildInfo.sncVersion = \"git${sncGitHash}\"" \
            | ${JQ} ".clusterInfo.openshiftVersion = \"${OKD_RELEASE}\"" \
            | ${JQ} ".clusterInfo.clusterName = \"${CRC_VM_NAME}\"" \
            | ${JQ} ".clusterInfo.baseDomain = \"${BASE_DOMAIN}\"" \
            | ${JQ} ".clusterInfo.appsDomain = \"apps-${CRC_VM_NAME}.${BASE_DOMAIN}\"" >${INSTALL_DIR}/crc-bundle-info.json
}

function generate_pv() {
  local pvdir="${1}"
  local name="${2}"
cat <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${name}
  labels:
    volume: ${name}
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteOnce
    - ReadWriteMany
    - ReadOnlyMany
  hostPath:
    path: ${pvdir}
  persistentVolumeReclaimPolicy: Recycle
EOF
}

function setup_pv_dirs() {
    local dir="${1}"
    local count="${2}"

    ${SSH} core@api.${CRC_VM_NAME}.${BASE_DOMAIN} 'sudo bash -x -s' <<EOF
    for pvsubdir in \$(seq -f "pv%04g" 1 ${count}); do
        mkdir -p "${dir}/\${pvsubdir}"
    done
    if ! chcon -R -t svirt_sandbox_file_t "${dir}" &> /dev/null; then
        echo "Failed to set SELinux context on ${dir}"
    fi
    chmod -R 770 ${dir}
EOF
}

function create_pvs() {
    local pvdir="${1}"
    local count="${2}"

    setup_pv_dirs "${pvdir}" "${count}"

    for pvname in $(seq -f "pv%04g" 1 ${count}); do
        if ! ${OC} get pv "${pvname}" &> /dev/null; then
            generate_pv "${pvdir}/${pvname}" "${pvname}" | ${OC} create -f -
        else
            echo "persistentvolume ${pvname} already exists"
        fi
    done

    # Apply registry pvc to bound with pv0001
    ${OC} apply -f registry_pvc.yaml

    # Add registry storage to pvc
    ${OC} patch config.imageregistry.operator.openshift.io/cluster --patch='[{"op": "add", "path": "/spec/storage/pvc", "value": {"claim": "crc-image-registry-storage"}}]' --type=json
    # Remove emptyDir as storage for registry
    ${OC} patch config.imageregistry.operator.openshift.io/cluster --patch='[{"op": "remove", "path": "/spec/storage/emptyDir"}]' --type=json
}

# This follows https://blog.openshift.com/enabling-openshift-4-clusters-to-stop-and-resume-cluster-vms/
# in order to trigger regeneration of the initial 24h certs the installer created on the cluster
function renew_certificates() {
    # Get the cli image from release payload and update it to bootstrap-cred-manager resource
    cli_image=$(${OC} adm release info ${OKD_REGISTRY}:${OKD_RELEASE} --image-for=cli)

    ${YQ} write --inplace kubelet-bootstrap-cred-manager-ds.yaml spec.template.spec.containers[0].image ${cli_image}

    ${OC} apply -f kubelet-bootstrap-cred-manager-ds.yaml

    # Delete the current csr signer to get new request.
    ${OC} delete secrets/csr-signer-signer secrets/csr-signer -n openshift-kube-controller-manager-operator

    # Wait for 5 min to make sure cluster is stable again.
    sleep 300

    # Remove the 24 hours certs and bootstrap kubeconfig
    # this kubeconfig will be regenerated and new certs will be created in pki folder
    # which will have 30 days validity.
    ${SSH} core@api.${CRC_VM_NAME}.${BASE_DOMAIN} -- sudo rm -fr /var/lib/kubelet/pki
    ${SSH} core@api.${CRC_VM_NAME}.${BASE_DOMAIN} -- sudo rm -fr /var/lib/kubelet/kubeconfig
    ${SSH} core@api.${CRC_VM_NAME}.${BASE_DOMAIN} -- sudo systemctl restart kubelet

    # Wait until bootstrap csr request is generated.
    until ${OC} get csr | grep Pending; do echo 'Waiting for first CSR request.'; sleep 2; done
    ${OC} get csr -oname | xargs ${OC} adm certificate approve

    delete_operator "daemonset/kubelet-bootstrap-cred-manager" "openshift-machine-config-operator" "k8s-app=kubelet-bootstrap-cred-manager"
}

# deletes an operator and wait until the resources it manages are gone.
function delete_operator() {
        local delete_object=$1
        local namespace=$2
        local pod_selector=$3

        pod=$(${OC} get pod -l ${pod_selector} -o jsonpath="{.items[0].metadata.name}" -n ${namespace})

        ${OC} delete ${delete_object} -n ${namespace}
        # Wait until the operator pod is deleted before trying to delete the resources it manages
        ${OC} wait --for=delete pod/${pod} --timeout=120s -n ${namespace} || ${OC} delete pod/${pod} --grace-period=0 --force -n ${namespace} || true
}

delete_operator "daemonset/kubelet-bootstrap-cred-manager" "openshift-machine-config-operator" "k8s-app=kubelet-bootstrap-cred-manager"

# Set the VM static hostname to crc-xxxxx-master-0 instead of localhost.localdomain
HOSTNAME=$(${SSH} core@api.${CRC_VM_NAME}.${BASE_DOMAIN} hostnamectl status --transient)
${SSH} core@api.${CRC_VM_NAME}.${BASE_DOMAIN} sudo hostnamectl set-hostname ${HOSTNAME}


# Create persistent volumes
create_pvs "${CRC_PV_DIR}" 30

# Mark some of the deployments unmanaged by the cluster-version-operator (CVO)
# https://github.com/openshift/cluster-version-operator/blob/master/docs/dev/clusterversion.md#setting-objects-unmanaged
${OC} patch clusterversion version --type json -p "$(cat cvo_override.yaml)"

# Clean-up 'openshift-monitoring' namespace
delete_operator "deployment/cluster-monitoring-operator" "openshift-monitoring" "app=cluster-monitoring-operator"
delete_operator "deployment/prometheus-operator" "openshift-monitoring" "app.kubernetes.io/name=prometheus-operator"
delete_operator "deployment/prometheus-adapter" "openshift-monitoring" "name=prometheus-adapter"
delete_operator "statefulset/alertmanager-main" "openshift-monitoring" "app=alertmanager"
${OC} delete statefulset,deployment,daemonset --all -n openshift-monitoring

# Delete the pods which are there in Complete state
${OC} delete pods -l 'app in (installer, pruner)' -n openshift-kube-apiserver
${OC} delete pods -l 'app in (installer, pruner)' -n openshift-kube-scheduler
${OC} delete pods -l 'app in (installer, pruner)' -n openshift-kube-controller-manager

# Clean-up 'openshift-machine-api' namespace
delete_operator "deployment/machine-api-operator" "openshift-machine-api" "k8s-app=machine-api-operator"
${OC} delete statefulset,deployment,daemonset --all -n openshift-machine-api

# Clean-up 'openshift-machine-config-operator' namespace
delete_operator "deployment/machine-config-operator" "openshift-machine-config-operator" "k8s-app=machine-config-operator"
${OC} delete statefulset,deployment,daemonset --all -n openshift-machine-config-operator

# Clean-up 'openshift-insights' namespace
${OC} delete statefulset,deployment,daemonset --all -n openshift-insights

# Clean-up 'openshift-cloud-credential-operator' namespace
${OC} delete statefulset,deployment,daemonset --all -n openshift-cloud-credential-operator

# Clean-up 'openshift-cluster-storage-operator' namespace
delete_operator "deployment.apps/csi-snapshot-controller-operator" "openshift-cluster-storage-operator" "app=csi-snapshot-controller-operator"
${OC} delete statefulset,deployment,daemonset --all -n openshift-cluster-storage-operator

# Clean-up 'openshift-kube-storage-version-migrator-operator' namespace
${OC} delete statefulset,deployment,daemonset --all -n openshift-kube-storage-version-migrator-operator

# Delete the v1beta1.metrics.k8s.io apiservice since we are already scale down cluster wide monitioring.
# Since this CRD block namespace deletion forever.
${OC} delete apiservice v1beta1.metrics.k8s.io

# Scale route deployment from 2 to 1
${OC} patch --patch='{"spec": {"replicas": 1}}' --type=merge ingresscontroller/default -n openshift-ingress-operator

# Set default route for registry CRD from false to true.
${OC} patch config.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
