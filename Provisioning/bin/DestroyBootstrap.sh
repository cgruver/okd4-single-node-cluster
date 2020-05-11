#!/bin/bash

# Destroy the VM
virsh destroy okd4-bootstrap
virsh undefine okd4-bootstrap
virsh pool-destroy okd4-bootstrap
virsh pool-undefine okd4-bootstrap
rm -rf /VirtualMachines/okd4-bootstrap

cat /etc/named/zones/db.${SNC_DOMAIN} | grep -v remove-after-bootstrap > /tmp/db.${SNC_DOMAIN}
mv /tmp/db.${SNC_DOMAIN} /etc/named/zones/db.${SNC_DOMAIN}
systemctl restart named.service

rm -f /tmp/bootstrap.iso
