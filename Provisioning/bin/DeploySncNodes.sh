#!/bin/bash

# This script will set up the infrastructure to deploy a single node OKD 4.X cluster
PULL_RELEASE=false
USE_MIRROR=false
IP_CONFIG=""
HOSTNAME="okd4-master-0"
CPU="4"
MEMORY="16384"
DISK="200"

for i in "$@"
do
case $i in
    -h=*|--hostname=*)
    HOSTNAME="${i#*=}"
    shift
    ;;
    -c=*|--cpu=*)
    CPU="${i#*=}"
    shift
    ;;
    -m=*|--memory=*)
    MEMORY="${i#*=}"
    shift
    ;;
    -d=*|--disk=*)
    DISK="${i#*=}"
    shift
    ;;
    -m|--mirror)
    USE_MIRROR=true
    shift
    ;;
    -p|--pull-release)
    PULL_RELEASE=true
    shift
    ;;
    *)
          # unknown option
    ;;
esac
done


# Pull the OKD release tooling identified by ${OKD_REGISTRY}:${OKD_RELEASE}.  i.e. OKD_REGISTRY=registry.svc.ci.openshift.org/origin/release, OKD_RELEASE=4.4.0-0.okd-2020-03-03-170958
if [ ${PULL_RELEASE} == "true" ]
then
  'sed -i "s|registry.svc.ci.openshift.org|;sinkhole|g" /etc/named/zones/db.sinkhole && systemctl restart named'
  mkdir -p ${OKD4_LAB_PATH}/okd-release-tmp
  cd ${OKD4_LAB_PATH}/okd-release-tmp
  oc adm release extract --command='openshift-install' ${OKD_REGISTRY}:${OKD_RELEASE}
  oc adm release extract --command='oc' ${OKD_REGISTRY}:${OKD_RELEASE}
  mv -f openshift-install ~/bin
  mv -f oc ~/bin
  cd ..
  rm -rf okd-release-tmp
fi
if [ ${USE_MIRROR} == "true" ]
then
  'sed -i "s|;sinkhole|registry.svc.ci.openshift.org|g" /etc/named/zones/db.sinkhole && systemctl restart named'
fi

# Create and deploy ignition files
rm -rf ${OKD4_LAB_PATH}/okd4-install-dir
mkdir ${OKD4_LAB_PATH}/okd4-install-dir
cp ${OKD4_LAB_PATH}/install-config-snc.yaml ${OKD4_LAB_PATH}/okd4-install-dir/install-config.yaml
OKD_VER=$(echo $OKD_RELEASE | sed  "s|4.4.0-0.okd|4.4|g")
sed -i "s|%%OKD_VER%%|${OKD_VER}|g" ${OKD4_LAB_PATH}/okd4-install-dir/install-config.yaml
openshift-install --dir=${OKD4_LAB_PATH}/okd4-install-dir create ignition-configs
scp -r ${OKD4_LAB_PATH}/okd4-install-dir/*.ign root@${INSTALL_HOST_IP}:${INSTALL_ROOT}/fcos/ignition/
chmod 644 ${INSTALL_ROOT}/fcos/ignition/*

mkdir -p ${OKD4_LAB_PATH}/ipxe-work-dir

# Get IP address for the OKD Node
IP_01=$(dig ${HOSTNAME}.${LAB_DOMAIN} +short)

# Create the OKD Node VM
mkdir -p /VirtualMachines/${HOSTNAME}
virt-install --print-xml 1 --name ${HOSTNAME} --memory ${MEMORY} --vcpus ${CPU} --boot=hd,network,menu=on,useserial=on --disk size=${DISK},path=/VirtualMachines/${HOSTNAME}/rootvol,bus=sata --network bridge=br0 --graphics none --noautoconsole --os-variant centos7.0 > /VirtualMachines/${HOSTNAME}.xml
virsh define /VirtualMachines/${HOSTNAME}.xml

# Get the MAC address for eth0 in the new VM  
var=$(virsh -q domiflist ${HOSTNAME} | grep br0)
NET_MAC=$(echo ${var} | cut -d" " -f5)
  
IP_CONFIG="ip=${IP_01}::${LAB_GATEWAY}:${LAB_NETMASK}:${HOSTNAME}.${LAB_DOMAIN}:eth0:none nameserver=${LAB_NAMESERVER}"

sed "s|%%IP_CONFIG%%|${IP_CONFIG}|g" ${OKD4_LAB_PATH}/ipxe-templates/fcos-okd4.ipxe > ${OKD4_LAB_PATH}/ipxe-work-dir/${NET_MAC//:/-}.ipxe
sed -i "s|%%OKD_ROLE%%|master|g" ${OKD4_LAB_PATH}/ipxe-work-dir/${NET_MAC//:/-}.ipxe
cp ${OKD4_LAB_PATH}/ipxe-work-dir/${NET_MAC//:/-}.ipxe /var/lib/tftpboot/ipxe/${NET_MAC//:/-}.ipxe

IP_CONFIG=""
IP_01=""

# Get IP address for Bootstrap Node
IP_01=$(dig okd4-bootstrap.${LAB_DOMAIN} +short)

# Create the Bootstrap Node VM
mkdir -p /VirtualMachines/okd4-bootstrap
virt-install --print-xml 1 --name okd4-bootstrap --memory 12288 --vcpus 4 --boot=hd,network,menu=on,useserial=on --disk size=50,path=/VirtualMachines/okd4-bootstrap/rootvol,bus=sata --network bridge=br0 --graphics none --noautoconsole --os-variant centos7.0 > /VirtualMachines/okd4-bootstrap.xml
virsh define /VirtualMachines/okd4-bootstrap.xml

# Get the MAC address for eth0 in the new VM  
var=$(virsh -q domiflist okd4-bootstrap | grep br0)
NET_MAC=$(echo ${var} | cut -d" " -f5)
  
IP_CONFIG="ip=${IP_01}::${LAB_GATEWAY}:${LAB_NETMASK}:okd4-bootstrap.${LAB_DOMAIN}:eth0:none nameserver=${LAB_NAMESERVER}"

sed "s|%%IP_CONFIG%%|${IP_CONFIG}|g" ${OKD4_LAB_PATH}/ipxe-templates/fcos-okd4.ipxe > ${OKD4_LAB_PATH}/ipxe-work-dir/${NET_MAC//:/-}.ipxe
sed -i "s|%%OKD_ROLE%%|bootstrap|g" ${OKD4_LAB_PATH}/ipxe-work-dir/${NET_MAC//:/-}.ipxe
cp ${OKD4_LAB_PATH}/ipxe-work-dir/${NET_MAC//:/-}.ipxe /var/lib/tftpboot/ipxe/${NET_MAC//:/-}.ipxe

rm -rf ${OKD4_LAB_PATH}/ipxe-work-dir

