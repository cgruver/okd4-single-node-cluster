#!/bin/bash

# This script will set up the infrastructure to deploy a single node OKD 4.X cluster
PULL_RELEASE=false
USE_MIRROR=false
CPU="4"
MEMORY="16384"
DISK="200"

for i in "$@"
do
case $i in
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
    *)
          # unknown option
    ;;
esac
done


# Pull the OKD release tooling identified by ${OKD_REGISTRY}:${OKD_RELEASE}.  i.e. OKD_REGISTRY=registry.svc.ci.openshift.org/origin/release, OKD_RELEASE=4.4.0-0.okd-2020-03-03-170958
mkdir -p ${OKD4_SNC_PATH}/okd-release-tmp
cd ${OKD4_SNC_PATH}/okd-release-tmp
oc adm release extract --command='openshift-install' ${OKD_REGISTRY}:${OKD_RELEASE}
oc adm release extract --command='oc' ${OKD_REGISTRY}:${OKD_RELEASE}
mv -f openshift-install ~/bin
mv -f oc ~/bin
cd ..
rm -rf okd-release-tmp

# Create and deploy ignition files
rm -rf ${OKD4_SNC_PATH}/okd4-install-dir
mkdir -p ${OKD4_SNC_PATH}/okd4-install-dir
cp ${OKD4_SNC_PATH}/install-config-snc.yaml ${OKD4_SNC_PATH}/okd4-install-dir/install-config.yaml
OKD_VER=$(echo $OKD_RELEASE | sed  "s|4.4.0-0.okd|4.4|g")
sed -i "s|%%OKD_VER%%|${OKD_VER}|g" ${OKD4_SNC_PATH}/okd4-install-dir/install-config.yaml
openshift-install --dir=${OKD4_SNC_PATH}/okd4-install-dir create ignition-configs
cp -r ${OKD4_SNC_PATH}/okd4-install-dir/*.ign ${INSTALL_ROOT}/fcos/ignition/
chmod 644 ${INSTALL_ROOT}/fcos/ignition/*

# Download FCOS images
curl -o ${INSTALL_ROOT}/fcos/vmlinuz https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live-kernel-x86_64
curl -o ${INSTALL_ROOT}/fcos/initrd https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live-initramfs.x86_64.img
curl -o ${INSTALL_ROOT}/fcos/install.xz https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-metal.x86_64.raw.xz
curl -o ${INSTALL_ROOT}/fcos/install.xz.sig https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-metal.x86_64.raw.xz.sig
curl -o /tmp/fcos.iso https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live.x86_64.iso

# Prepare FCOS boot ISO
mkdir /tmp/{fcos-iso,fcos}
mount -o loop /tmp/fcos.iso /tmp/fcos-iso
rsync -av /tmp/fcos-iso/ /tmp/fcos/
umount /tmp/fcos-iso
rm -rf /tmp/fcos-iso
rm -f /tmp/fcos.iso

# Get IP address for Bootstrap Node
IP=""
IP=$(dig okd4-snc-bootstrap.${SNC_DOMAIN} +short)

# Create ISO Image for Bootstrap
cat << EOF > /tmp/fcos/isolinux/isolinux.cfg
serial 0
default vesamenu.c32
timeout 1
display boot.msg
menu clear
menu separator
label linux
  menu label ^Fedora CoreOS (Live)
  menu default
  kernel /images/vmlinuz
  append initrd=/images/initramfs.img "ip=${IP}::${SNC_GATEWAY}:${SNC_NETMASK}:${HOSTNAME}.${SNC_DOMAIN}:eth0:none nameserver=${SNC_NAMESERVER}" rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=sda coreos.inst.image_url=${INSTALL_URL}/fcos/install.xz coreos.inst.ignition_url=${INSTALL_URL}/fcos/ignition/bootstrap.ign coreos.inst.platform_id=qemu console=ttyS0
menu separator
menu end
EOF

mkisofs -o /tmp/bootstrap.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -r /tmp/fcos/

# Create the Bootstrap Node VM
mkdir -p /VirtualMachines/okd4-snc-bootstrap
virt-install --name okd4-snc-bootstrap --memory 14336 --vcpus 2 --disk size=100,path=/VirtualMachines/okd4-snc-bootstrap/rootvol,bus=sata --cdrom /tmp/bootstrap.iso --network bridge=br0 --graphics none --noautoconsole --os-variant centos7.0

IP=""

# Get IP address for the OKD Node
IP=$(dig okd4-snc-master.${SNC_DOMAIN} +short)

# Create ISO Image for Master
cat << EOF > /tmp/fcos/isolinux/isolinux.cfg
serial 0
default vesamenu.c32
timeout 1
display boot.msg
menu clear
menu separator
label linux
  menu label ^Fedora CoreOS (Live)
  menu default
  kernel /images/vmlinuz
  append initrd=/images/initramfs.img ip=${IP}::${SNC_GATEWAY}:${SNC_NETMASK}:${HOSTNAME}.${SNC_DOMAIN}:eth0:none nameserver=${SNC_NAMESERVER} rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=sda coreos.inst.image_url=${INSTALL_URL}/fcos/install.xz coreos.inst.ignition_url=${INSTALL_URL}/fcos/ignition/master.ign coreos.inst.platform_id=qemu console=ttyS0
menu separator
menu end
EOF

mkisofs -o /tmp/snc-master.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -r /tmp/fcos/

# Create the OKD Node VM
mkdir -p /VirtualMachines/okd4-snc-master
virt-install --name okd4-snc-master --memory ${MEMORY} --vcpus ${CPU} --disk size=${DISK},path=/VirtualMachines/okd4-snc-master/rootvol,bus=sata --cdrom /tmp/snc-master.iso --network bridge=br0 --graphics none --noautoconsole --os-variant centos7.0

rm -rf /tmp/fcos