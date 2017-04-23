#!/bin/bash
ME=$0

export DIR="$(dirname $0)"
export INSTANCE=$2

if [ "$NS_DEBUG" = "1" ]; then
  set -x
fi

function nsr_init {
  case $1 in
    "start")
      nsr_start $2
      ;;
    "restart")
      nsr_stop $2
      nsr_start $2
      ;;
    "stop")
      nsr_stop $2
      ;;
    "inside")
      nsr_inside $2
      ;;
    "reload")
      nsr_reload $2
      ;;
    "reload_inside")
      nsr_reload_inside $2
      ;;
    *)
      echo "Usage: $ME <start|stop|restart|reload> <instance>"
      exit 1
      ;;
  esac
}


function nsr_start {
  IF_VAR="IF_$1"
  IF_LIST=${!IF_VAR}
  export INST_DIR="$DIR/instance/$1"

  if [ "$IF_LIST" = "" ] && [ -f "$INST_DIR/interfaces" ]; then
    IF_LIST=$(cat "$INST_DIR/interfaces")
  fi

  if [ "$IF_LIST" = "" ]; then
    echo "Fatal: No interfaces specified for instance $1"
    echo "Set environment variable IF_$1, example: IF_$1=\"eth1 wifi0\""
    echo "This will map eth1 to eth0 and wifi0 to eth1"
    exit 1
  fi

  if [ ! -d "$INST_DIR" ]; then
    mkdir -p "$INST_DIR"
  fi

  for script in start stop reload; do
    if [ ! -f "$INST_DIR/$script.sh" ]; then
      echo "#!/bin/bash" > "$INST_DIR/$script.sh"
      chmod a+x "$INST_DIR/$script.sh"
      echo "Created script: $INST_DIR/$script.sh"
    fi
  done

  if [ -f /var/run/netns/$1 ]; then
    echo "Instance already started, try restart"
    exit 0
  fi
  ip netns add $1 || exit 1
 
  VETH=0
  while ip link show dev veth$VETH >/dev/null 2>&1;
    do VETH=$[ $VETH + 1 ]
  done
 
  IF_CNT=0
  IF_NAME="${1}-eth"

  echo "$IF_LIST" > "$INST_DIR/interfaces"

  for IF in $IF_LIST; do
    ip link add ${IF_NAME}${IF_CNT} type veth peer veth$VETH || (
      echo "Unable to create interface: ${IF_NAME}${IF_CNT} linked to veth$VETH"
      ip link del ${IF_NAME}${IF_CNT}
      nsr_stop_internal $1
      exit 1
    ) || exit 1
    ip link set dev veth$VETH netns $1 || (
      echo "Unable to move interface int-${IF_NAME}${IF_CNT} to namespace ${1}"
      ip link del ${IF_NAME}${IF_CNT}
      nsr_stop_internal $1
      exit 1
    ) || exit 1
    ip netns exec $1 ip link set dev veth$VETH name eth${IF_CNT}
    ip link set ${IF_NAME}${IF_CNT} up
    brctl addif $IF ${IF_NAME}${IF_CNT}
    IF_CNT=$[IF_CNT + 1]
  done

  ip netns exec $1 $ME inside $1
  nsr_stop_internal $1
}

function nsr_stop {
  export INST_DIR="$DIR/instance/$1"
  if [ -f "$INST_DIR/pid" ]; then
    pid=$(cat "$INST_DIR/pid")
    if [ -d /proc/$pid ]; then
      kill $pid
    else
      nsr_stop_internal $1
      exit 0
    fi
  else
    nsr_stop_internal $1
    exit 0
  fi
  
  # 100 x 0.2 = 20 seconds
  wait=100

  while [ $wait -gt 0 ]; do
    if [ ! -f /var/run/netns/$1 ]; then
      exit 0
    fi
    sleep 0.2
    wait=$[ $wait - 1 ]
  done

  # Force stop
  nsr_stop_internal $1
}

function nsr_stop_internal {
  export INST_DIR="$DIR/instance/$1"
  IF_LIST="$(cat "$INST_DIR/interfaces")"
  if [ -f /var/run/netns/$1 ]; then
    [ -x "$INST_DIR/stop.sh" ] && ip netns exec $1 "$INST_DIR/stop.sh"
    if [ -d "$INST_DIR" ]; then
      if [ -f "$INST_DIR/interfaces" ]; then
        IF_CNT=0
        for IF in $IF_LIST; do
          ip netns exec $1 ip link del eth${IF_CNT} >/dev/null 2>&1
          IF_CNT=$[IF_CNT + 1]
        done
      fi
    fi
    for IF in $IF_LIST; do
      ip link del ${1}-eth${IF_CNT} >/dev/null 2>&1
      IF_CNT=$[IF_CNT + 1]
    done
    ip netns del $1
  fi
}

function nsr_inside {
  export INST_DIR="$DIR/instance/$1"
  echo $$ > $INST_DIR/pid
  ip link set dev lo up
  sysctl net.ipv4.ip_forward=1
  sysctl net.ipv6.conf.all.forwarding=1
  [ -x "${INST_DIR}/start.sh" ] && "${INST_DIR}/start.sh"
  nsr_reload_inside $1
  while true; do sleep 9999; done
}

function nsr_reload_inside {
  export INST_DIR="$DIR/instance/$1"
  [ -x "${INST_DIR}/reload.sh" ] && "${INST_DIR}/reload.sh"
}

function nsr_reload {
  ip netns exec $1 $ME reload_inside $1 
}

nsr_init $1 $2

