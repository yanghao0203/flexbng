#!/bin/bash
##############################################################
# File Name: install-flexbng.sh
# Version: V1.0
# Author: weiyc
# Organization: netElastic
# Created Time : 2017-03-02 15:10:00
# Description: Flexbng initialization
##############################################################

DOWNLOAD_DIR=$(cd `dirname $0`; pwd)
VBRAS_DIR=/home/vBras
KVM_DIR=$VBRAS_DIR/kvm-imgs
stage=0

function echo_stage()
{
    let stage++
    echo
    echo "------------------------------------------------------------------"
    echo "Stage[${stage}]  $1"
    echo "------------------------------------------------------------------"
}

function build_fm10k()
{
    echo_stage "Build && Install FM10000 driver"
    cd $DOWNLOAD_DIR

    tar zxvf fm10k-0.19.6.tar.gz
    if [ $? -ne 0 ]; then
        echo "Untar fm10k-0.19.6.tar.gz failture!"
        exit 1
    fi

    cd fm10k-0.19.6/src
    make install
    if [ $? -ne 0 ]; then
        echo "Build & Install FM10000 driver failture!"
        exit 1
    fi
    modprobe fm10k
}

function vfio_onboot()
{
    echo_stage "Configure vfio driver on boot"
    cd $DOWNLOAD_DIR
    cp vfio.modules /etc/sysconfig/modules
}

function confid_libvirt()
{
    echo_stage "Configure libvirt"
    cat << EOF >> /etc/libvirt/qemu.conf
user = "root"

grout = "root"
EOF
}

function install_ovs()
{
    echo_stage "Build && Install openvswitch-2.3.3"
    cd $DOWNLOAD_DIR
    tar zxf openvswitch-2.3.3.tar.gz
    if [ $? -ne 0 ]; then
        echo "Untar openvswitch-2.3.3.tar.gz failture!"
        exit 1
    fi

    cd openvswitch-2.3.3
    ./configure
    make
    make install
    mkdir -p /usr/local/etc/openvswitch
    /usr/local/bin/ovsdb-tool create /usr/local/etc/openvswitch/conf.db vswitchd/vswitch.ovsschema
    if [ $? -ne 0 ]; then
        echo "Build & Install openvswitch-2.3.3.tar.gz failture!"
        exit 1
    fi
    echo -e "Build & Install openvswitch-2.3.3.tar.gz success!\n"
}

function config_ovs()
{
    # auto start script
    cd $DOWNLOAD_DIR
    test -e flexbng.service && cp -vaf flexbng.service /etc/systemd/system/flexbng.service
    chmod +x /etc/systemd/system/flexbng.service
    test -e flexbng-auto-start && cp -vaf flexbng-auto-start /etc/init.d/flexbng-auto-start
    chmod +x /etc/init.d/flexbng-auto-start
}

function config_env()
{
    echo_stage "Config running environment"
    # DNS
    echo "nameserver 8.8.8.8" > /etc/resolv.conf

    # enable service
    systemctl enable flexbng.service
    systemctl enable libvirtd.service

    # config issue
    cat << EOF > /etc/issue
######################################################
#      Welcome to the netElastic Flexbng server      #
######################################################
\S
Kernel \r on an \m

Default administrator login:    root
Default administrator password: netElastic

Please change root password on first login.

EOF
}

echo "================================Begin================================"
install_ovs

build_fm10k

confid_libvirt

config_ovs

config_env

vfio_onboot
echo "================================The End==============================="
