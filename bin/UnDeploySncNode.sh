#!/bin/bash

# Destroy the VM
virsh destroy okd4-snc-master
virsh undefine okd4-snc-master
virsh pool-destroy okd4-snc-master
virsh pool-undefine okd4-snc-master
rm -rf /VirtualMachines/okd4-snc-master

