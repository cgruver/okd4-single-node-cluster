#!/bin/bash

set -x

# This script will set up the infrastructure to deploy a single node OKD 4.X cluster
CPU="4"
MEMORY="16384"
DISK="200"
FCOS_VER=32.20200601.3.0
FCOS_STREAM=stable

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

curl -o ${INSTALL_ROOT}/fcos/install.xz https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-metal.x86_64.raw.xz
curl -o ${INSTALL_ROOT}/fcos/install.xz.sig https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-metal.x86_64.raw.xz.sig

# Download Syslinux
curl -o ${OKD4_SNC_PATH}/syslinux-6.03.tar.xz https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
tar -xf ${OKD4_SNC_PATH}/syslinux-6.03.tar.xz -C ${OKD4_SNC_PATH}/

# Prepare FCOS boot ISO
mkdir -p ${OKD4_SNC_PATH}/fcos-iso/{isolinux,images}
curl -o ${OKD4_SNC_PATH}/fcos-iso/images/vmlinuz https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live-kernel-x86_64
curl -o ${OKD4_SNC_PATH}/fcos-iso/images/initramfs.img https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live-initramfs.x86_64.img
cp ${OKD4_SNC_PATH}/syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 ${OKD4_SNC_PATH}/fcos-iso/isolinux/ldlinux.c32
cp ${OKD4_SNC_PATH}/syslinux-6.03/bios/core/isolinux.bin ${OKD4_SNC_PATH}/fcos-iso/isolinux/isolinux.bin
cp ${OKD4_SNC_PATH}/syslinux-6.03/bios/com32/menu/vesamenu.c32 ${OKD4_SNC_PATH}/fcos-iso/isolinux/vesamenu.c32
cp ${OKD4_SNC_PATH}/syslinux-6.03/bios/com32/lib/libcom32.c32 ${OKD4_SNC_PATH}/fcos-iso/isolinux/libcom32.c32
cp ${OKD4_SNC_PATH}/syslinux-6.03/bios/com32/libutil/libutil.c32 ${OKD4_SNC_PATH}/fcos-iso/isolinux/libutil.c32

# Get IP address for Bootstrap Node
IP=""
IP=$(dig okd4-snc-bootstrap.${SNC_DOMAIN} +short)

# Create ISO Image for Bootstrap
cat << EOF > ${OKD4_SNC_PATH}/fcos-iso/isolinux/isolinux.cfg
serial 0
default vesamenu.c32
timeout 1
menu clear
menu separator
label linux
  menu label ^Fedora CoreOS (Live)
  menu default
  kernel /images/vmlinuz
  append initrd=/images/initramfs.img ip=${IP}::${SNC_GATEWAY}:${SNC_NETMASK}:okd4-snc-bootstrap.${SNC_DOMAIN}:eth0:none nameserver=${SNC_NAMESERVER} rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=${INSTALL_URL}/fcos/ignition/bootstrap.ign coreos.inst.platform_id=qemu console=ttyS0
menu separator
menu end
EOF

mkisofs -o /tmp/bootstrap.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -r ${OKD4_SNC_PATH}/fcos-iso/

# Create the Bootstrap Node VM
mkdir -p /VirtualMachines/okd4-snc-bootstrap
virt-install --name okd4-snc-bootstrap --memory 14336 --vcpus 2 --disk size=100,path=/VirtualMachines/okd4-snc-bootstrap/rootvol,bus=sata --cdrom /tmp/bootstrap.iso --network bridge=br0 --graphics none --noautoconsole --os-variant centos7.0

IP=""

# Get IP address for the OKD Node
IP=$(dig okd4-snc-master.${SNC_DOMAIN} +short)

# Create ISO Image for Master
cat << EOF > ${OKD4_SNC_PATH}/fcos-iso/isolinux/isolinux.cfg
serial 0
default vesamenu.c32
timeout 1
menu clear
menu separator
label linux
  menu label ^Fedora CoreOS (Live)
  menu default
  kernel /images/vmlinuz
  append initrd=/images/initramfs.img ip=${IP}::${SNC_GATEWAY}:${SNC_NETMASK}:okd4-snc-master.${SNC_DOMAIN}:eth0:none nameserver=${SNC_NAMESERVER} rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/sda coreos.inst.image_url=${INSTALL_URL}/fcos/install.xz coreos.inst.ignition_url=${INSTALL_URL}/fcos/ignition/master.ign coreos.inst.platform_id=qemu console=ttyS0
menu separator
menu end
EOF

mkisofs -o /tmp/snc-master.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -r ${OKD4_SNC_PATH}/fcos-iso/

# Create the OKD Node VM
mkdir -p /VirtualMachines/okd4-snc-master
virt-install --name okd4-snc-master --memory ${MEMORY} --vcpus ${CPU} --disk size=${DISK},path=/VirtualMachines/okd4-snc-master/rootvol,bus=sata --cdrom /tmp/snc-master.iso --network bridge=br0 --graphics none --noautoconsole --os-variant centos7.0

rm -rf ${OKD4_SNC_PATH}/fcos-iso
