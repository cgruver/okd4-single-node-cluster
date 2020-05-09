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

# Destroy the VM
virsh destroy ${HOSTNAME}
virsh undefine ${HOSTNAME}
virsh pool-destroy ${HOSTNAME}
virsh pool-undefine ${HOSTNAME}
rm -rf /VirtualMachines/${HOSTNAME}

