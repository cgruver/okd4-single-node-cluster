#!/bin/bash

for i in "$@"
do
  case $i in
    -h=*|--hostname=*)
    HOSTNAME="${i#*=}"
    shift # past argument=value
    ;;
    *)
          # unknown option
    ;;
  esac
done

var=$(virsh -q domiflist ${HOSTNAME} | grep br0)
NET_MAC=$(echo ${var} | cut -d" " -f5)

# Remove the iPXE boot file
rm -f /var/lib/tftpboot/ipxe/${NET_MAC//:/-}.ipxe

# Destroy the VM
virsh destroy ${HOSTNAME}
virsh undefine ${HOSTNAME}
virsh pool-destroy ${HOSTNAME}
virsh pool-undefine ${HOSTNAME}
rm -rf /VirtualMachines/${HOSTNAME}

