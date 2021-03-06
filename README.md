# nsRouter - Run routing in its own namespace!

## Status of project
This project is currently only a Proof-of-Concept and should not be considered stable.

## Prerequisites
You need to have a linux kernel with support for namespaces, iproute2 + tools installed,
knowledge of scripting and linux bridges

## How?
First, you need to set up bridges for all networks you want access from nsRouter.
Check the documentation for your distribution on how to set up persistant bridges (the commands below only works until reboot)

```bash
# Do this locally, since you might break network connectivity
brctl addbr br0
brctl addif br0 enp7s0f0
brctl addbr br1
brctl addif br0 enp7s0f1
```

Secondly, create your first nsRouter instance (named `wan` below)
```bash
IF_wan="br0 br1" ./router.sh start wan
```

The environment variable `IF_{name}` is used initially when setting up the instance for the first time.

Within the namespace, the first interface is named eth0, the second eth1, etc.
Outside the namespace, the interfaces are named wan-eth0, wan-eth1, etc (prefixed with instance name).

Running `brctl show` should give you something like this:
```
bridge name     bridge id               STP enabled     interfaces
br0             8000.000000000001       no              enp7s0f0
                                                        wan-eth0
br1             8000.000000000002       no              enp7s0f1
                                                        wan-eth1
```

An `instance/wan/` folder should also have been created in the same directory as the `router.sh` script containing:
```
$ ls -l instance/wan/
-rw-r--r-- 1 usr grp   8 Apr 23 02:03 interfaces
-rwxr-xr-x 1 usr grp  12 Apr 23 02:05 reload.sh
-rwxr-xr-x 1 usr grp  12 Apr 23 02:04 start.sh
-rwxr-xr-x 1 usr grp  12 Apr 23 02:05 stop.sh
```

`interfaces` contains a list of which bridges that the instance should join.

`start.sh`, `stop.sh` and `reload.sh` are scripts where you can specify what should happen when starting/stopping/reloading the instance.

You can use the environment variables `$INSTANCE` to get the name of the instance and `$INST_DIR` to get the path to the instance directory within your scripts.

See the samples in [instance/](instance/) for sample instances.

To stop the instance again, run:
```bash
./router.sh stop wan
```

You can also run nsRouter with systemd, install [nsrouter@.service](nsrouter@.service) in /etc/systemd/system.

After installing the unit file, you can start the `wan` instance again by running `systemctl start nsrouter@wan.service`

## Debugging
You can use `router.sh enter` command to run commands in the nsRouter namespace, for example:
```
# router.sh enter wan bash
Running command "bash" in namespace wan
# netstat -antup
Active Internet connections (servers and established)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
udp        0      0 0.0.0.0:68              0.0.0.0:*                           89539/dhclient
# exit
#
```
(feels nice to not have any unnecessary services binding to your WAN ip!)

`FORWARD` rules in the system namespace might affect the bridge. To avoid that, set these in sysctl:
```
net.bridge.bridge-nf-call-iptables=0
net.bridge.bridge-nf-call-ip6tables=0
```

## Why?
I have my own home server that does both internet sharing and runs different services, doing both is sometimes a headache and installing
something new might break internet access.

My main reasons for creating this project are:
* Certain daemons (I'm looking at you docker) messes with my iptables rules
* I want to easily isolate IoT devices in their own network
* I don't want to maintain a complex firewall that solves all my needs - this allows me to split up the configuration in multiple isolated firewalls
* Hacking is fun

## TODO
* [ ] Investigate if `PrivateNetwork` in systemd can be used instead of `ip netns`
* [ ] Support non-bridge interfaces (move interface to namespace)
* [ ] Rewrite in Go
