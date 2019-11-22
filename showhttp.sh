#!/usr/bin/env bash

# M: network namespace setup from https://gist.github.com/dpino/6c0dca1742093346461e11aa8f608a99

set -x

# Must be unique
NS="showhttp"
VETH="veth5"
VPEER="vpeer5"
VETH_ADDR="10.201.1.1"
VPEER_ADDR="10.201.1.2"

if [[ $EUID -ne 0 ]]; then
    echo "You must be root to run this script"
    exit 1
fi

# Remove namespace if it exists.
ip netns del $NS &>/dev/null

# Create namespace
ip netns add $NS

# Create veth link.
ip link add ${VETH} type veth peer name ${VPEER}

# Add peer-1 to NS.
ip link set ${VPEER} netns $NS

# Setup IP address of ${VETH}.
ip addr add ${VETH_ADDR}/24 dev ${VETH}
ip link set ${VETH} up

# Setup IP ${VPEER}.
ip netns exec $NS ip addr add ${VPEER_ADDR}/24 dev ${VPEER}
ip netns exec $NS ip link set ${VPEER} up
ip netns exec $NS ip link set lo up
ip netns exec $NS ip route add default via ${VETH_ADDR}

# Enable IP-forwarding.
echo 1 > /proc/sys/net/ipv4/ip_forward

# Flush forward rules.
iptables -P FORWARD DROP
iptables -F FORWARD
 
# Flush nat rules.
iptables -t nat -F

# Enable masquerading of 10.200.1.0.
# TODO: Look up or specify interface, don't hardcode wlp2s0
iptables -t nat -A POSTROUTING -s ${VPEER_ADDR}/24 -o wlp2s0 -j MASQUERADE

 
iptables -A FORWARD -i wlp2s0 -o ${VETH} -j ACCEPT
iptables -A FORWARD -o wlp2s0 -i ${VETH} -j ACCEPT

mkdir -p /etc/netns/$NS/
echo 'nameserver 8.8.8.8' > /etc/netns/$NS/resolv.conf

tcpdump -i ${VETH} -w /tmp/.showhttp &
TCPDUMP_PID=$!

# Get into namespace
# ip netns exec ${NS} /bin/bash --rcfile <(echo "PS1=\"${NS}> \"")

# OR

# Do the command we're watching
ip netns exec ${NS} $@ > /dev/null

# TODO: Garbage hack for now because ip netns exec runs as a bg task and I cant get the pid for some reason
sleep 5

# Kill tcpdump
kill $TCPDUMP_PID

# Clean up namespace
ip netns del ${NS}

# Filter the captured output for http (TODO: Needs some cleaning up)
tcpdump -r /tmp/.showhttp -A -s 30000 -v 'tcp and (((ip[2:2] - ((ip[0]&0xf)<<2)) - ((tcp[12]&0xf0)>>2)) != 0)'
