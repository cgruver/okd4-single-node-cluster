#!/bin/bash

set -x

# This script will set up the infrastructure to deploy a single node OKD 4.X cluster
CPU="4"
MEMORY="16384"
DISK="200"
FCOS_VER=33.20201201.3.0
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

function configOkdNode() {
    
  local ip_addr=${1}
  local host_name=${2}
  local mac=${3}
  local role=${4}

cat << EOF > ${OKD4_SNC_PATH}/work-dir/ignition/${role}.yml
variant: fcos
version: 1.1.0
ignition:
  config:
    merge:
      - local: ${role}.ign
storage:
  files:
    - path: /etc/zincati/config.d/90-disable-feature.toml
      mode: 0644
      contents:
        inline: |
          [updates]
          enabled = false
    - path: /etc/systemd/network/25-nic0.link
      mode: 0644
      contents:
        inline: |
          [Match]
          MACAddress=${mac}
          [Link]
          Name=nic0
    - path: /etc/NetworkManager/system-connections/nic0.nmconnection
      mode: 0600
      overwrite: true
      contents:
        inline: |
          [connection]
          type=ethernet
          interface-name=nic0
          [ethernet]
          mac-address=${mac}
          [ipv4]
          method=manual
          addresses=${ip_addr}/${SNC_NETMASK}
          gateway=${SNC_GATEWAY}
          dns=${SNC_NAMESERVER}
          dns-search=${SNC_DOMAIN}
    - path: /etc/hostname
      mode: 0420
      overwrite: true
      contents:
        inline: |
          ${host_name}
EOF
}

# Generate MAC addresses for the master and bootstrap nodes:
BOOT_MAC=$(date +%s | md5sum | head -c 6 | sed -e 's/\([0-9A-Fa-f]\{2\}\)/\1:/g' -e 's/\(.*\):$/\1/' | sed -e 's/^/52:54:00:/')
sleep 2
MASTER_MAC=$(date +%s | md5sum | head -c 6 | sed -e 's/\([0-9A-Fa-f]\{2\}\)/\1:/g' -e 's/\(.*\):$/\1/' | sed -e 's/^/52:54:00:/')

# Get the IP addresses for the master and bootstrap nodes:
BOOT_IP=$(dig okd4-snc-bootstrap.${SNC_DOMAIN} +short)
MASTER_IP=$(dig okd4-snc-master.${SNC_DOMAIN} +short)

# Pull the OKD release tooling identified by ${OKD_REGISTRY}:${OKD_RELEASE}.  i.e. OKD_REGISTRY=registry.svc.ci.openshift.org/origin/release, OKD_RELEASE=4.4.0-0.okd-2020-03-03-170958
mkdir -p ${OKD4_SNC_PATH}/okd-release-tmp
cd ${OKD4_SNC_PATH}/okd-release-tmp
oc adm release extract --command='openshift-install' ${OKD_REGISTRY}:${OKD_RELEASE}
oc adm release extract --command='oc' ${OKD_REGISTRY}:${OKD_RELEASE}
mv -f openshift-install ~/bin
mv -f oc ~/bin
cd ..
rm -rf okd-release-tmp

# Download fcct
rm -rf ${OKD4_SNC_PATH}/work-dir
mkdir -p ${OKD4_SNC_PATH}/work-dir/ignition
wget https://github.com/coreos/fcct/releases/download/v0.6.0/fcct-x86_64-unknown-linux-gnu
mv fcct-x86_64-unknown-linux-gnu ${OKD4_SNC_PATH}/work-dir/fcct 
chmod 750 ${OKD4_SNC_PATH}/work-dir/fcct

# Create and deploy ignition files
rm -rf ${OKD4_SNC_PATH}/okd4-install-dir
mkdir -p ${OKD4_SNC_PATH}/okd4-install-dir
cp ${OKD4_SNC_PATH}/install-config-snc.yaml ${OKD4_SNC_PATH}/okd4-install-dir/install-config.yaml
OKD_VER=$(echo $OKD_RELEASE | sed  "s|4.4.0-0.okd|4.4|g")
sed -i "s|%%OKD_VER%%|${OKD_VER}|g" ${OKD4_SNC_PATH}/okd4-install-dir/install-config.yaml
openshift-install --dir=${OKD4_SNC_PATH}/okd4-install-dir create ignition-configs

# Modify ignition files for IP config:
configOkdNode ${BOOT_IP} okd4-snc-bootstrap.${SNC_DOMAIN} ${BOOT_MAC} bootstrap
configOkdNode ${MASTER_IP} okd4-snc-master.${SNC_DOMAIN} ${MASTER_MAC} master
cat ${OKD4_SNC_PATH}/work-dir/ignition/bootstrap.yml | ${OKD4_SNC_PATH}/work-dir/fcct -d ${OKD4_SNC_PATH}/okd4-install-dir/ -o ${OKD4_SNC_PATH}/work-dir/ignition/bootstrap.ign
cat ${OKD4_SNC_PATH}/work-dir/ignition/master.yml | ${OKD4_SNC_PATH}/work-dir/fcct -d ${OKD4_SNC_PATH}/okd4-install-dir/ -o ${OKD4_SNC_PATH}/work-dir/ignition/master.ign

cp -r ${OKD4_SNC_PATH}/work-dir/ignition/*.ign ${INSTALL_ROOT}/fcos/ignition/
chmod 644 ${INSTALL_ROOT}/fcos/ignition/*


# Download Syslinux
curl -o ${OKD4_SNC_PATH}/syslinux-6.03.tar.xz https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.03.tar.xz
tar -xf ${OKD4_SNC_PATH}/syslinux-6.03.tar.xz -C ${OKD4_SNC_PATH}/

# Prepare FCOS boot ISO
mkdir -p ${OKD4_SNC_PATH}/fcos-iso/{isolinux,images}
curl -o ${OKD4_SNC_PATH}/fcos-iso/images/vmlinuz https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live-kernel-x86_64
curl -o ${OKD4_SNC_PATH}/fcos-iso/images/initramfs.img https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live-initramfs.x86_64.img
curl -o ${OKD4_SNC_PATH}/fcos-iso/images/rootfs.img https://builds.coreos.fedoraproject.org/prod/streams/${FCOS_STREAM}/builds/${FCOS_VER}/x86_64/fedora-coreos-${FCOS_VER}-live-rootfs.x86_64.img


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
  append initrd=/images/initramfs.img initrd=/images/rootfs.img net.ifnames=1 ifname=nic0:${BOOT_MAC} ip=${IP}::${SNC_GATEWAY}:${SNC_NETMASK}:okd4-snc-bootstrap.${SNC_DOMAIN}:nic0:none nameserver=${SNC_NAMESERVER} rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=${INSTALL_URL}/fcos/ignition/bootstrap.ign coreos.inst.platform_id=qemu console=ttyS0
menu separator
menu end
EOF

mkisofs -o /tmp/bootstrap.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -r ${OKD4_SNC_PATH}/fcos-iso/

# Create the Bootstrap Node VM
mkdir -p /VirtualMachines/okd4-snc-bootstrap
virt-install --name okd4-snc-bootstrap --memory 14336 --vcpus 2 --disk size=100,path=/VirtualMachines/okd4-snc-bootstrap/rootvol,bus=sata --cdrom /tmp/bootstrap.iso --network bridge=br0 --mac=${BOOT_MAC} --graphics none --noautoconsole --os-variant centos7.0

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
  append initrd=/images/initramfs.img initrd=/images/rootfs.img net.ifnames=1 ifname=nic0:${MASTER_MAC} ip=${IP}::${SNC_GATEWAY}:${SNC_NETMASK}:okd4-snc-master.${SNC_DOMAIN}:nic0:none nameserver=${SNC_NAMESERVER} rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=/dev/sda coreos.inst.ignition_url=${INSTALL_URL}/fcos/ignition/master.ign coreos.inst.platform_id=qemu console=ttyS0
menu separator
menu end
EOF

mkisofs -o /tmp/snc-master.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -r ${OKD4_SNC_PATH}/fcos-iso/

# Create the OKD Node VM
mkdir -p /VirtualMachines/okd4-snc-master
virt-install --name okd4-snc-master --memory ${MEMORY} --vcpus ${CPU} --disk size=${DISK},path=/VirtualMachines/okd4-snc-master/rootvol,bus=sata --cdrom /tmp/snc-master.iso --network bridge=br0 --mac=${MASTER_MAC} --graphics none --noautoconsole --os-variant centos7.0

rm -rf ${OKD4_SNC_PATH}/fcos-iso
