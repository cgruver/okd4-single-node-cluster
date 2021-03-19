#!/bin/bash

set -x

dnf -y module install virt
dnf -y install wget git net-tools bind bind-utils bash-completion rsync libguestfs-tools virt-install epel-release libvirt-devel httpd-tools nginx

ssh-keygen -t ecdsa -b 521 -N "" -f /root/.ssh/id_ecdsa_crc

systemctl enable libvirtd --now

mkdir /VirtualMachines
virsh pool-destroy default
virsh pool-undefine default
virsh pool-define-as --name default --type dir --target /VirtualMachines
virsh pool-autostart default
virsh pool-start default

firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-service=dns
firewall-cmd --reload

systemctl enable nginx --now
mkdir -p /usr/share/nginx/html/install/fcos/ignition

cp ./DNS/named.conf /etc
cp -r ./DNS/named /etc

mv /etc/named/zones/db.domain.records /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%SNC_NETWORK%%|${SNC_DOMAIN}|g" /etc/named.conf
sed -i "s|%%SNC_NETWORK%%|${SNC_DOMAIN}|g" /etc/named.conf
sed -i "s|%%SNC_HOST%%|${SNC_HOST}|g" /etc/named.conf

sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/named.conf.local
sed -i "s|%%SNC_ARPA%%|${SNC_ARPA}|g" /etc/named/named.conf.local

sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%SNC_HOST%%|${SNC_HOST}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%BOOTSTRAP_HOST%%|${BOOTSTRAP_HOST}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%MASTER_HOST%%|${MASTER_HOST}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%SNC_NETWORK%%|${SNC_NETWORK}|g" /etc/named/zones/db.${SNC_DOMAIN}

sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/zones/db.snc_subnet
sed -i "s|%%SNC_HOST%%|${SNC_HOST}|g" /etc/named/zones/db.snc_subnet
sed -i "s|%%MASTER_HOST%%|${MASTER_HOST}|g" /etc/named/zones/db.snc_subnet
sed -i "s|%%BOOTSTRAP_HOST%%|${BOOTSTRAP_HOST}|g" /etc/named/zones/db.snc_subnet

named-checkconf
systemctl enable named --now

nmcli connection add type bridge ifname br0 con-name br0 ipv4.method manual ipv4.address "${SNC_HOST}/24" ipv4.gateway "${SNC_GATEWAY}" ipv4.dns "${SNC_NAMESERVER}" ipv4.dns-search "${SNC_DOMAIN}" ipv4.never-default no connection.autoconnect yes bridge.stp no ipv6.method ignore 
nmcli con add type ethernet con-name br0-slave-1 ifname ${PRIMARY_NIC} master br0
nmcli con del ${PRIMARY_NIC}
nmcli con add type ethernet con-name ${PRIMARY_NIC} ifname ${PRIMARY_NIC} connection.autoconnect no ipv4.method disabled ipv6.method ignore
systemctl restart NetworkManager.service
