#!/bin/bash

# Destroy the VM
virsh destroy okd4-snc-bootstrap
virsh undefine okd4-snc-bootstrap
virsh pool-destroy okd4-snc-bootstrap
virsh pool-undefine okd4-snc-bootstrap
rm -rf /VirtualMachines/okd4-snc-bootstrap

cat /etc/named/zones/db.${SNC_DOMAIN} | grep -v remove-after-bootstrap > /tmp/db.${SNC_DOMAIN}
mv /tmp/db.${SNC_DOMAIN} /etc/named/zones/db.${SNC_DOMAIN}
systemctl restart named.service

rm -f /tmp/bootstrap.iso
