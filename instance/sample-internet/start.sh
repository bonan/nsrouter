#!/bin/bash

DIR=$(dirname $0)

ip link set dev eth0 address 12:34:56:78:90:AB
ip link set dev eth1 up address 12:34:56:78:90:CD

ip addr add 192.168.0.1/24 dev eth1

dhclient -cf $DIR/dhclient.conf -lf /var/lib/dhcp/dhclient.$INSTANCE.leases -pf /var/run/dhclient.$INSTANCE.pid eth0

