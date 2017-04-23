#!/bin/bash

iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -t nat -P PREROUTING ACCEPT
iptables -t nat -P OUTPUT ACCEPT
iptables -t nat -P POSTROUTING ACCEPT

iptables -F
iptables -X
iptables -F -t nat
iptables -X -t nat

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
