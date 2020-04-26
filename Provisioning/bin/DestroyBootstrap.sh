#!/bin/bash

var=$(virsh -q domiflist okd4-bootstrap | grep br0)
NET_MAC=$(echo ${var} | cut -d" " -f5)

# Remove the iPXE boot file
rm -f /var/lib/tftpboot/ipxe/${NET_MAC//:/-}.ipxe

# Destroy the VM
virsh destroy okd4-bootstrap
virsh undefine okd4-bootstrap
virsh pool-destroy okd4-bootstrap
virsh pool-undefine okd4-bootstrap
rm -rf /VirtualMachines/okd4-bootstrap

