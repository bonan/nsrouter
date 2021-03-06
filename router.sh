#!/bin/bash
ME=$0

INIT_CMD=$1
shift
export INSTANCE=$1
shift

export DIR="$(dirname $0)"
export NS_CMD="$*"

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
    "enter")
      if [ ! -f $DIR/instance/$2/pid ]; then
        echo "Namespace $2 is not started"
        exit 1
      fi
      pid=$(cat $DIR/instance/$2/pid)
      if [ ! -x /proc/$pid ]; then
        echo "Namespace $2 is not started"
        exit 1
      fi
      echo "Running command \"${NS_CMD}\" in namespace $2"
      nsenter -t $pid -m -n -u $NS_CMD
      ;;
    *)
      echo "Usage: $ME <start|stop|restart|reload|enter> <instance> <command>"
      exit 1
      ;;
  esac
}

function nsr_custom {
  if [ -f "$INST_DIR/custom.sh" ]; then
    . $INST_DIR/custom.sh $*
    return $?
  fi
  return 0
}

function nsr_start {
  IF_VAR="IF_$1"
  IF_LIST=${!IF_VAR}
  export INST_DIR="$DIR/instance/$1"

  # Tears down everything
  # $1 Message
  # $2 Interface to delete
  function fail {
    echo $1
    if [[ ! -z $2 ]]; then
      ip link del $2
    fi
    nsr_stop_internal $INSTANCE
    exit 1
  }

  if [ ! -d "$INST_DIR" ]; then
    mkdir -p "$INST_DIR"
  fi

  if [ "$IF_LIST" = "" ] && [ -f "$INST_DIR/interfaces" ]; then
    IF_LIST=$(cat "$INST_DIR/interfaces")
  else
    echo "$IF_LIST" > "$INST_DIR/interfaces"
  fi

  if [ "$IF_LIST" = "" ]; then
    echo "Fatal: No interfaces specified for instance $1"
    echo "Set environment variable IF_$1, example: IF_$1=\"eth1 wifi0\""
    echo "This will map eth1 to eth0 and wifi0 to eth1"
    exit 1
  fi

  for script in start stop reload; do
    if [ ! -f "$INST_DIR/$script.sh" ]; then
      echo "#!/bin/bash" > "$INST_DIR/$script.sh"
      chmod a+x "$INST_DIR/$script.sh"
      echo "Created script: $INST_DIR/$script.sh"
    fi
  done

  if [ -f /var/run/netns/$1 ]; then
    echo "Instance already started or namespace already exists, try restart"
    exit 2
  fi
  ip netns add $1 || (echo "Unable to create namespace $1"; false) || exit 3
 
  VETH=0
  while ip link show dev veth$VETH >/dev/null 2>&1;
    do VETH=$[ $VETH + 1 ]
  done
 
  IF_CNT=0
  IF_NAME="${1}-eth"


  for IF in $IF_LIST; do
    BRIDGE=$(ip link show dev $IF)
    export NAME="${IF_NAME}${IF_CNT}"

    nsr_custom $1 $IF $NAME eth${IF_CNT}
    if [ $? -eq 0 ]; then
      if [ "$BRIDGE" = "" ]; then
        echo "Bridge $IF doesn't exist, trying to create it"
        ip link add $IF type bridge || fail "Unable to create bridge $IF" || exit 32
        ip link set $IF up || fail "Unable to start bridge $IF" || exit 33
      fi

      echo "Bringing up $NAME (bridge $IF):"
      ip link add $NAME type veth peer name eth${IF_CNT} netns $1 || fail "Unable to create interface $NAME" $NAME || exit 34

      # Join outside interface to bridge
      ip link set dev $NAME up master $IF || fail "Unable to join $NAME to bridge $IF" || exit 37
    fi
    IF_CNT=$[IF_CNT + 1]
  done

  trap "nsr_stop_internal $1" SIGINT SIGTERM

  mkdir -p /var/run/nsrouter/$1
  cat /etc/resolv.conf > /var/run/nsrouter/$1/resolv.conf
  grep -vE $(hostname) /etc/hosts > /var/run/nsrouter/$1/hosts
  ip netns exec $1 unshare -m -u $ME inside $1 $NS_CMD
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
      exit $?
    fi
  else
    nsr_stop_internal $1
    exit $?
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
  exit $?
}

function nsr_stop_internal {
  echo "nsrouter stopping"
  export INST_DIR="$DIR/instance/$1"
  IF_LIST="$(cat "$INST_DIR/interfaces")"
  if [ -f /var/run/netns/$1 ]; then
    [ -x "$INST_DIR/stop.sh" ] && ip netns exec $1 "$INST_DIR/stop.sh"
    if [ -d "$INST_DIR" ]; then
      if [ -f "$INST_DIR/interfaces" ]; then
        IF_CNT=0
        for IF in $IF_LIST; do
          echo -n "Bringing down eth${IF_CNT}: "
          ip netns exec $1 ip link del eth${IF_CNT} && echo "."
          IF_CNT=$[IF_CNT + 1]
        done
      fi
    fi
    echo -n "Deleting namespace: "
    ip netns del $1 && echo "."
  fi
  IF_CNT=0
  for IF in $IF_LIST; do
    ip link del ${1}-eth${IF_CNT} >/dev/null 2>&1
    IF_CNT=$[IF_CNT + 1]
  done
  [ -f $INST_DIR/pid ] && rm $INST_DIR/pid
}

function nsr_inside {
  mount -o bind /var/run/nsrouter/$1/resolv.conf /etc/resolv.conf
  mount -o bind /var/run/nsrouter/$1/hosts /etc/hosts
  hostname $(hostname)-$1
  echo "127.0.1.1 $(hostname --fqdn) $(hostname)" >> /etc/hosts
  export INST_DIR="$DIR/instance/$1"
  echo $$ > $INST_DIR/pid
  ip link set dev lo up
  sysctl net.ipv4.ip_forward=1
  sysctl net.ipv6.conf.all.forwarding=1
  [ -x "${INST_DIR}/start.sh" ] && "${INST_DIR}/start.sh"
  nsr_reload_inside $1 || exit 1
  ip addr show
  ip route show
  if [ ! -z "$NS_CMD" ]; then
    echo "Starting $NS_CMD:"
    $NS_CMD
  else
    echo "Successfully started with pid $$, use kill or ^C to shut down nsrouter"
    while true; do sleep 3600; done
  fi
}

function nsr_reload_inside {
  export INST_DIR="$DIR/instance/$1"
  [ -x "${INST_DIR}/reload.sh" ] && "${INST_DIR}/reload.sh" 
}

function nsr_reload {
  ip netns exec $1 $ME reload_inside $1 
}

nsr_init $INIT_CMD $INSTANCE
exit $?
