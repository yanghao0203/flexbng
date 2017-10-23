#!/bin/bash
##############################################################
# File Name: fetch-res.sh
# Version: V1.0
# Author: weiyc
# Organization: certusnet
# Created Time : 2017-03-02 15:10:00
# Description: Fetch Flexbng resource (from ftp or usb/cdrom devices)
##############################################################

DOWNLOAD_DIR=$(cd `dirname $0`; pwd)
stage=0

function echo_stage()
{
    let stage++
    echo
    echo "------------------------------------------------------------------"
    echo "Stage[${stage}]  $1"
    echo "------------------------------------------------------------------"
}

function ftp_get()
{
    if [ "$1" == "" ]; then
        echo "ftp_get url is null...continue..."
        return
    fi

    echo "Ftp download \"$2\" from \"$1\""
    cd $DOWNLOAD_DIR
    wget -nv $1/$2
    if [ $? -ne 0 ]; then
        echo "Download failture!";
        exit 1;
    fi
}

function local_get()
{
    if [ "$1" == "" ]; then
        echo "local_get file is null...continue..."
        return
    fi

    echo "Local copy \"$2\" from \"$1\""
    test -e $1/$2 && cp $1/$2 $DOWNLOAD_DIR
}


echo "================================Begin================================"



# Download
FILES=(
extra-pkts/openvswitch-2.3.3.tar.gz
extra-pkts/fm10k-0.19.6.tar.gz
kvm-song/centos7.1-FlexBNG-common-v1.0.qcow2
kvm-song/FWA-1010VC/all.xml
kvm-song/FWA-1010VC/user_data-all
kvm-song/FWA-1010VC/Step1.start-ovs.sh
kvm-song/FWA-1010VC/flexbng.service
kvm-song/FWA-1010VC/flexbng-auto-start
kvm-song/FWA-1010VC/dpdk_nic_bind.py
kvm-song/FWA-1010VC/flexbng_install.sh
kvm-song/FWA-1010VC/flexbng.service
KVM-song/FWA-1010VC/song-atm-B33P2-debug.all.tar.gz
)

case "$1" in
    "ftp")
        echo_stage "Download resource from $2"
        for e in ${FILES[@]}; do
            ftp_get $2 $e
        done
        ;;
    "local")
        echo_stage "Copy resource from $2"
        for e in ${FILES[@]}; do
            local_get $2 $e
        done
        ;;
esac


echo "================================The End================================"
