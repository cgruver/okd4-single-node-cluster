# Notes before they become docs

Set Masters as Infra nodes

    for i in 0 1 2
    do
      oc label nodes okd4-master-${i}.${LAB_DOMAIN} node-role.kubernetes.io/infra=""
    done

    oc patch -n openshift-ingress-operator ingresscontroller default --patch '{"spec":{"nodePlacement":{"nodeSelector":{"matchLabels":{"node-role.kubernetes.io/infra":""}}}}}' --type=merge

    oc get pod -n openshift-ingress -o wide

    oc patch scheduler cluster --patch '{"spec":{"mastersSchedulable":false}}' --type=merge

Deploy Load Balancer

    DeployLabGuest.sh -h=okd4-prd-lb01 -n=bastion -r=lb-node -c=2 -m=4096 -d=50 -v=7000

Set up HTPasswd

    mkdir -p ${OKD4_LAB_PATH}/okd-creds
    ADMIN_PWD=$(cat ${OKD4_LAB_PATH}/okd4-install-dir/auth/kubeadmin-password)
    htpasswd -B -c -b ${OKD4_LAB_PATH}/okd-creds/htpasswd admin $(cat ${OKD4_LAB_PATH}/okd4-install-dir/auth/kubeadmin-password)
    htpasswd -b ${OKD4_LAB_PATH}/okd-creds/htpasswd devuser devpwd
    oc create -n openshift-config secret generic htpasswd-secret --from-file=htpasswd=${OKD4_LAB_PATH}/okd-creds/htpasswd
    oc apply -f ${OKD4_LAB_PATH}/htpasswd-cr.yml
    oc adm policy add-cluster-role-to-user cluster-admin admin

Remove temporary user:

    oc delete secrets kubeadmin -n kube-system

Expose Registry:

    oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
    docker login -u $(oc whoami) -p $(oc whoami -t) --tls-verify=false $(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')

Reset the HA Proxy configuration for a new cluster build:

    ssh okd4-lb01 "curl -o /etc/haproxy/haproxy.cfg http://${INSTALL_HOST_IP}/install/postinstall/haproxy.cfg && systemctl restart haproxy"
    
Upgrade:

    oc adm upgrade 

    Cluster version is 4.4.0-0.okd-2020-04-09-104654

    Updates:

    VERSION                       IMAGE
    4.4.0-0.okd-2020-04-09-113408 registry.svc.ci.openshift.org/origin/release@sha256:724d170530bd738830f0ba370e74d94a22fc70cf1c017b1d1447d39ae7c3cf4f
    4.4.0-0.okd-2020-04-09-124138 registry.svc.ci.openshift.org/origin/release@sha256:ce16ac845c0a0d178149553a51214367f63860aea71c0337f25556f25e5b8bb3

    ssh root@${LAB_NAMESERVER} 'sed -i "s|registry.svc.ci.openshift.org|;sinkhole|g" /etc/named/zones/db.sinkhole && systemctl restart named'

    export OKD_RELEASE=4.4.0-0.okd-2020-04-09-124138

    oc adm -a ${LOCAL_SECRET_JSON} release mirror --from=${OKD_REGISTRY}:${OKD_RELEASE} --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OKD_RELEASE}

    oc apply -f upgrade.yaml

    ssh root@${LAB_NAMESERVER} 'sed -i "s|;sinkhole|registry.svc.ci.openshift.org|g" /etc/named/zones/db.sinkhole && systemctl restart named'

    oc adm upgrade --to=${OKD_RELEASE}


    oc patch clusterversion/version --patch '{"spec":{"upstream":"https://origin-release.svc.ci.openshift.org/graph"}}' --type=merge

Add PVC to Registry:

    
    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":"registry-pvc"}}}}'

    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"emptyDir":{}}}}'

    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Removed"}}'

    oc patch configs.imageregistry.operator.openshift.io cluster --type json -p '[{ "op": "remove", "path": "/spec/storage/emptyDir" }]'

    oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"rolloutStrategy":"Recreate","managementState":"Managed","storage":{"pvc":{"claim":"registry-pvc"}}}}'

Samples Operator: Extract templates and image streams, then remove the operator.  We don't want everything and the kitchen sink...

    mkdir -p ${OKD4_LAB_PATH}/OKD-Templates-ImageStreams/templates
    mkdir ${OKD4_LAB_PATH}/OKD-Templates-ImageStreams/image-streams
    oc project openshift
    oc get template | grep -v NAME | while read line
    do
       TEMPLATE=$(echo $line | cut -d' ' -f1)
       oc get --export template ${TEMPLATE} -o yaml > ${OKD4_LAB_PATH}/OKD-Templates-ImageStreams/templates/${TEMPLATE}.yml
    done

    oc get is | grep -v NAME | while read line
    do
       IS=$(echo $line | cut -d' ' -f1)
       oc get --export is ${IS} -o yaml > ${OKD4_LAB_PATH}/OKD-Templates-ImageStreams/image-streams/${IS}.yml
    done

    oc patch configs.samples.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Removed"}}'

Tekton:

    tkn clustertask ls

    IMAGE_REGISTRY=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
    podman login -u $(oc whoami) -p $(oc whoami -t) --tls-verify=false ${IMAGE_REGISTRY}
    podman pull quay.io/openshift/origin-cli:4.4.0
    podman tag quay.io/openshift/origin-cli:4.4.0 ${IMAGE_REGISTRY}/openshift/origin-cli:4.4.0
    podman push ${IMAGE_REGISTRY}/openshift/origin-cli:4.4.0 --tls-verify=false

    docker pull quay.io/buildah/stable
    docker tag quay.io/buildah/stable:latest ${IMAGE_REGISTRY}/openshift/buildah:stable
    docker push ${IMAGE_REGISTRY}/openshift/buildah:stable

    docker pull docker.io/maven:3.6.3-jdk-8-slim
    docker tag docker.io/library/maven:3.6.3-jdk-8-slim ${IMAGE_REGISTRY}/openshift/maven:3.6.3-jdk-8-slim
    docker push ${IMAGE_REGISTRY}/openshift/maven:3.6.3-jdk-8-slim

    docker pull quay.io/openshift/origin-cli:4.4.0
    docker tag quay.io/openshift/origin-cli:4.4.0 ${IMAGE_REGISTRY}/openshift/origin-cli:4.4.0
    docker push ${IMAGE_REGISTRY}/openshift/origin-cli:4.4.0

    oc patch sa pipeline --type merge --patch '{"secrets":[{"name":"bitbucket-secret"}]}'

Fix Hostname:

    for i in 0 1 2 ; do ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-master-${i}.${LAB_DOMAIN} "sudo hostnamectl set-hostname okd4-master-${i}.my.domain.org && sudo shutdown -r now"; done
    for i in 0 1 2 ; do ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-worker-${i}.${LAB_DOMAIN} "sudo hostnamectl set-hostname okd4-worker-${i}.my.domain.org && sudo shutdown -r now"; done

Logs:

    for i in 0 1 2 ; do echo "okd4-master-${i}" ; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-master-${i}.${LAB_DOMAIN} "sudo journalctl --disk-usage"; done
    for i in 0 1 2 ; do echo "okd4-master-${i}" ; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-worker-${i}.${LAB_DOMAIN} "sudo journalctl --disk-usage"; done

    for i in 0 1 2 ; do echo "okd4-master-${i}" ; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-master-${i}.${LAB_DOMAIN} "sudo journalctl --vacuum-time=1s"; done
    for i in 0 1 2 ; do echo "okd4-master-${i}" ; ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null core@okd4-worker-${i}.${LAB_DOMAIN} "sudo journalctl --vacuum-time=1s"; done