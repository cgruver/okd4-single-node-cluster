#!/bin/bash

set -x

A1=$(echo ${SNC_NETWORK} | cut -d"." -f1)
A2=$(echo ${SNC_NETWORK} | cut -d"." -f2)
A3=$(echo ${SNC_NETWORK} | cut -d"." -f3)
SNC_ARPA=${A3}.${A2}.${A1}

/usr/bin/cp ${OKD4_SNC_PATH}/okd4-single-node-cluster/DNS/named.conf /etc
/usr/bin/cp -r ${OKD4_SNC_PATH}/okd4-single-node-cluster/DNS/named /etc

/usr/bin/mv /etc/named/zones/db.domain.records /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named.conf
sed -i "s|%%SNC_NETWORK%%|${SNC_NETWORK}|g" /etc/named.conf
sed -i "s|%%SNC_HOST%%|${SNC_HOST}|g" /etc/named.conf

sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/named.conf.local
sed -i "s|%%SNC_ARPA%%|${SNC_ARPA}|g" /etc/named/named.conf.local

sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%SNC_HOST%%|${SNC_HOST}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%BOOTSTRAP_HOST%%|${BOOTSTRAP_HOST}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%MASTER_HOST%%|${MASTER_HOST}|g" /etc/named/zones/db.${SNC_DOMAIN}
sed -i "s|%%SNC_NETWORK%%|${SNC_NETWORK}|g" /etc/named/zones/db.${SNC_DOMAIN}

sed -i "s|%%SNC_DOMAIN%%|${SNC_DOMAIN}|g" /etc/named/zones/db.snc_ptr
sed -i "s|%%SNC_HOST%%|$(echo ${SNC_HOST} | cut -d"." -f4)|g" /etc/named/zones/db.snc_ptr
sed -i "s|%%MASTER_HOST%%|$(echo ${MASTER_HOST} | cut -d"." -f4)|g" /etc/named/zones/db.snc_ptr
sed -i "s|%%BOOTSTRAP_HOST%%|$(echo ${BOOTSTRAP_HOST} | cut -d"." -f4)|g" /etc/named/zones/db.snc_ptr

systemctl restart named
