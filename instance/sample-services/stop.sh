#!/bin/bash

for p in $INST_DIR/*.pid; do
  pid=$(cat $p)
  if [ -x /proc/$pid ]; then
    kill $(cat $p)
  fi
  rm $p
done
