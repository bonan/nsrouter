#!/bin/bash

sysctl net.ipv4.ip_forward=0
sysctl net.ipv6.conf.all.forwarding=0

ip link set dev eth0 up address 12:34:56:78:90:EF

ip addr add 192.168.0.2/24 dev eth0
ip route add default via 192.168.0.1

dnsmasq \
 --listen-address=192.168.0.2 \
 --group=nogroup \
 --user=dnsmasq \
 --interface=eth0 \
 --dhcp-authoritative \
 --domain=mydomain.local \
 --dhcp-leasefile="$INST_DIR/dnsmasq.eth0.leases" \
 --pid-file="$INST_DIR/dnsmasq.eth0.pid" \
 --bind-interfaces \
 --dhcp-range=192.168.0.10,192.168.0.250,255.255.255.0,12h \
 --dhcp-option=option:router,192.168.0.1
 
