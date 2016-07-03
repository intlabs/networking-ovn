#!/usr/bin/env bash

# Script Arguments:
# $1 - ovn-controller IP address
# $2 - ovn-db IP address
OVN_CONTROLLER_IP=$1
OVN_DB_IP=$2

cp networking-ovn/devstack/computenode-local.conf.sample devstack/local.conf
sed -i -e 's/<IP address of host running everything else>/'$OVN_CONTROLLER_IP'/g' devstack/local.conf

sudo umount /opt/stack/data/nova/instances

# Get the IP address
ipaddress=$(ip -4 addr show eth1 | grep -oP "(?<=inet ).*(?=/)")

# Fixup HOST_IP with the local IP address
sed -i -e 's/<IP address of current host>/'$ipaddress'/g' devstack/local.conf

# Adjust some things in local.conf
cat << DEVSTACKEOF >> devstack/local.conf

# Set this to the address of the main DevStack host running the rest of the
# OpenStack services.
Q_HOST=$1
HOSTNAME=$(hostname)
OVN_SB_REMOTE=tcp:$OVN_DB_IP:6642
OVN_NB_REMOTE=tcp:$OVN_DB_IP:6641

# Enable logging to files.
LOGFILE=/opt/stack/log/stack.sh.log
SCREEN_LOGDIR=/opt/stack/log/data

# Enable the DHCP and metadata services on the compute node.
enable_service q-dhcp q-meta

# Whether to enable using OVN's L3 functionality. If this value is disabled,
# OpenStack will use the q-l3 functionality.  If you set OVN_L3_MODE to False,
# you must also enable the q-l3 service.
# By default OVN_L3_MODE is True
OVN_L3_MODE=False
enable_service q-l3
#disable_service q-l3

# Until OVN supports NAT, the private network IP address range
# must not conflict with IP address ranges on the host. Change
# as necessary for your environment.
NETWORK_GATEWAY=172.16.1.1
FIXED_RANGE=172.16.1.0/24
DEVSTACKEOF

# Add unique post-config for DevStack here using a separate 'cat' with
# single quotes around EOF to prevent interpretation of variables such
# as $Q_DHCP_CONF_FILE.

cat << 'DEVSTACKEOF' >> devstack/local.conf

# Set the availablity zone name (default is nova) for the DHCP service.
[[post-config|$Q_DHCP_CONF_FILE]]
[AGENT]
availability_zone = nova
DEVSTACKEOF

devstack/stack.sh

# Build the provider network in OVN. You can enable instances to access
# external networks such as the Internet by using the IP address of the host
# vboxnet interface for the provider network (typically vboxnet1) as the
# gateway for the subnet on the neutron provider network. Also requires
# enabling IP forwarding and configuring SNAT on the host. See the README for
# more information.

source /vagrant/provisioning/provider-setup.sh

provider_setup

# Add host route for the private network, at least until the native L3 agent
# supports NAT.
# FIXME(mkassawara): Add support for IPv6.
source devstack/openrc admin admin
ROUTER_GATEWAY=`neutron port-list -c fixed_ips -c device_owner | grep router_gateway | awk -F'ip_address'  '{ print $2 }' | cut -f3 -d\"`
sudo ip route add $FIXED_RANGE via $ROUTER_GATEWAY


# Set the OVN_*_DB variables to enable OVN commands using a remote database.
echo -e "\n# Enable OVN commands using a remote database.
export OVN_NB_DB=$OVN_NB_REMOTE
export OVN_SB_DB=$OVN_SB_REMOTE" >> ~/.bash_profile
