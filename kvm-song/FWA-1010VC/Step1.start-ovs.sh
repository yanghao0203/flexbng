#!/bin/bash

mgr_br="br_mgmt"
comm_br="br_comm"
intl_br="br_intl"

function kill_process()
{
    ID=`ps -ef| grep -E "$1"|grep -v 'grep'|awk '{print $2}'`
    for pid in $ID
    do
        kill -9 $pid
    done
}

echo "Kill ovsdb-server..."
kill_process "ovsdb-server"

echo "Kill ovs-vswitchd..."
kill_process "ovs-vswitchd"

sleep 2
echo "Modprobe openvswitch..."
modprobe openvswitch
echo "OK!"

echo "Start ovsdb-server..."
ovsdb-server --remote=punix:/usr/local/var/run/openvswitch/db.sock \
                     --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
                     --private-key=db:Open_vSwitch,SSL,private_key \
                     --certificate=db:Open_vSwitch,SSL,certificate \
                     --bootstrap-ca-cert=db:Open_vSwitch,SSL,ca_cert \
                     --pidfile --detach
echo "OK!"

echo "Start ovs daemon..."
ovs-vswitchd --pidfile --detach
echo "OK!"

sleep 2

echo "Start create manage bridge [$mgr_br]"

ovs-vsctl add-br $mgr_br
ifconfig $mgr_br 192.169.1.1/24  up

echo "Start create communication bridge [$comm_br]"

#ovs-vsctl add-br $comm_br
#ifconfig $comm_br 192.168.100.1/24  up

#echo "Start create internel bridge [$intl_br]"
#ovs-vsctl add-br $intl_br
#ifconfig $intl_br 0  up
#ifconfig $intl_br mtu 9000


echo "clear iptables"
iptables -F
iptables -X

echo "reset hugepages..."
mkdir /dev/hugepages2M
mount -t hugetlbfs -o pagesize=2M none /dev/hugepages2M
