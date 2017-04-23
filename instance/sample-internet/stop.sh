#!/bin/bash

if [ -f /var/run/dhclient.$INSTANCE.pid ]; then
  kill $(cat /var/run/dhclient.$INSTANCE.pid)
fi

