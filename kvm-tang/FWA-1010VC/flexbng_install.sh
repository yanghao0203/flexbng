#!/bin/bash
##############################################################
# File Name: flexbng_install.sh
# Version: V1.0
# Author: yangh
# Organization: certusnet
# Created Time : 2017-09-11 
# Description:  system initialization
##############################################################
action=$1
device_name=()
DOWNLOAD_DIR=$(cd `dirname $0`; pwd)
VBRAS_DIR=/home/vBras
KVM_DIR=$VBRAS_DIR/kvm-imgs

function start_ovs()
{
   mkdir -p $VBRAS_DIR
   mkdir -p $KVM_DIR
   cp -vaf Step*.sh $VBRAS_DIR
   chmod +x $VBRAS_DIR/*.sh
   echo "Start openvswitch"
   $VBRAS_DIR/Step1.start-ovs.sh
}

function system_check()
{
   echo -n "Check iommu...."
   iommu_status=`grep -i "iommu" /etc/grub2.cfg  | wc -l`
   if [ $iommu_status = 0 ];then
      echo Fail
   else 
      echo Success
   fi

   echo -n "Check vfio-pci...."
   vfio_status=`lsmod | grep vfio_pci | wc -l`
   if [ $vfio_status = 0 ];then
      echo Fail
   else 
      echo Success
   fi
   
   echo -n "Check libvirtd service...."
   libvirtd_status=`ps aux|grep libvirt |grep -v grep | wc -l`
   if [ $libvirtd_status = 0 ];then
      echo Fail
   else
      echo Success
   fi
   
   echo -n "Check openvswitch service...."
   ovs_status=`ps aux|grep ovs |grep -v grep | wc -l`
   if [ $ovs_status = 0 ];then
      echo Fail
   else 
      echo Success
   fi

   if  [[ $iommu_status > 0 ]]&&[[ $vfio_status > 0 ]]&&[[ $libvirtd_status > 0 ]]&&[[ $ovs_status > 0 ]];then
       echo "Success"
   else 
       echo "Please check the envirement."
       echo "exit."
       exit 1
   fi
}

function device_info()
{
   device_list=`lspci -Dvmmn | awk '/0200/{print a}{a=$0}' | awk -F" " '{print $2}'`
   i=0
   temp=()
   for device in $device_list 
       do
           driver=`lspci -vmmks $device | grep Driver | awk -F" " '{print $2}'`
           if [ $driver == vfio-pci ];then 
              continue
           fi
           device_mode=`lspci -vmmks $device | grep Device | awk -F: '{print $2}'`
           ifname=`ls /sys/bus/pci/drivers/$driver/$device/net`
           mac=`cat /sys/bus/pci/drivers/$driver/$device/net/*/address`
           numa_node=`cat /sys/bus/pci/drivers/$driver/$device/numa_node`
           if [ -z $action ];then
              action=default
           elif [ $action == "--status" ];then
               echo "=============================="
               echo "slot:      "$device
               echo "ifname:    "$ifname
               echo "mac:       "$mac
               echo "NUMA node: "$numa_node
               echo "Device:   "$device_mode
               echo "=============================="
           fi
           temp[0]=$i
           temp[1]=$ifname
           temp[2]=$device
           temp[3]=$mac
           temp[4]=$numa_node
           device_name[$i]=${temp[@]}
           i=`expr $i + 1`
       done
    #echo ${device_name[@]}
    #for j in "${device_name[@]}" ; do
    #    temp=($j)
    #    echo ${temp[1]} ${temp[2]} ${temp[3]}
    #done
}


function device_ovs_bind()
{
   echo "id   ifname"
   for j in "${device_name[@]}" ; do
       temp=($j)
       echo [${temp[0]}]: ${temp[1]}
   done
   echo -n "Choose the device:"
   read -a id
   if [ -z $id ]; then
      echo "Please input device id."
      exit
   fi
 
   n=1
   for i in "${id[@]}" ; do
      for j in "${device_name[@]}" ;do
         temp=($j)
         if [ "$i" == "${temp[0]}" ] ; then
            ovs-vsctl add-br br-fwd$n        
            ovs-vsctl add-port br-fwd$n ${temp[1]}
            n=`expr $n + 1`
         fi
      done
   done
}

function cpu_isolate()
{
    numa_node=0
    temp_list=`numactl --hardware | grep "node $numa_node cpus" | awk -F: '{print $2}'`
    echo "Current cpu list:"
    echo $temp_list

    echo  -n  "Choose the cpu you want to isolate:"
    read temp1_list                                                                                                                                        

    for i in ${temp1_list[@]};do
       if [ -z $cpu_list ];then
          cpu_list=$i
       else
          cpu_list=$cpu_list","$i
       fi
     done
    echo "cpu list will be isolated:"
    echo $cpu_list
    sed -i "s/115200n8/& isolcpus=$cpu_list/g" /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
    
}

function capacity_config()
{
  echo "test"
}

function hugepage()
{
     echo 1000 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages
     sed -i -e '/reset/a\echo 1000 > /sys/devices/system/node/node0/hugepages/hugepages-2048kB/nr_hugepages' $VBRAS_DIR/Step1.start-ovs.sh
}

function bng_ovs_init()
{
    touch fwd_file
    touch user_data_temp
    fwdbr_list=`ovs-vsctl show |grep Bridge | grep fwd | awk '{print $2}'` 
    echo ${fwdbr_list[@]}
    i=1
    for br in ${fwdbr_list[@]};do 
       s=`printf "%x\n" $((16#$i+8))`
       mac=aa:bb:cc:dd:d2:$i$i
      cat >> fwd_file <<EOF
<interface type='bridge'>
    <mac address='$mac'/>
    <source bridge='$br'/>
    <model type='e1000'/>
    <virtualport type='openvswitch'/>
    <target dev='fwd$i'/>
    <address type='pci' domain='0x0000' bus='0x00' slot='0x0$s' function='0x0'/>
</interface> 
EOF
      cat >> user_data_temp <<EOF
<interface>
    <service_type>forwarding</service_type>
    <network_type>E-LAN-L2</network_type>
    <seq_id>$i</seq_id>
    <mac_address>$mac</mac_address>
    <speed>10000M</speed>
</interface>
EOF
    i=`expr $i + 1`
   done
 
    echo "Adding ovs vnic config to all.xml"
    sed -i 's/^/        /g' fwd_file
    sed -i '/<serial/i\ temp' all.xml
    sed -i '/temp/r fwd_file' all.xml
    sed -i '/temp/d' all.xml
    dos2unix all.xml
    rm -rf fwd_file

    echo "Adding ovs vnic config to user_data"
    sed -i 's/^/            /g' user_data_temp
    sed -i '/<network_interfaces/r user_data_temp' user_data-all
    j=`grep "seq_id" user_data-all | wc -l`
    for ((i=2;i<=j;i++));do
      a=`expr $i - 2`
      sed -i "/<seq_id>.*/{x;s/^/./;/^\.\{$i\}$/{x;s/.*/                <seq_id>$a<\/seq_id>/;x};x;}" user_data-all
    done
    rm -rf user_data_temp
}

function create_bng()
{
    echo "Create bng..."

    cd $DOWNLOAD_DIR
    # kvm image configure
    if [ -e centos7.1-FlexBNG-common-v1.0.qcow2 ];then
        chmod 755 centos7.1-FlexBNG-common-v1.0.qcow2
        cp -vaf centos7.1-FlexBNG-common-v1.0.qcow2 $KVM_DIR/all.qcow2

        # user_data backup file
        cp -vaf user_data-all $KVM_DIR

        # virsh xml
        cp -vaf all.xml $KVM_DIR

        # init script
        cp -vaf Step*.sh $VBRAS_DIR
        chmod +x $VBRAS_DIR/*.sh

        #create vm
        virsh define $KVM_DIR/all.xml

        #copy user-data to all.qcow2
        cp -vaf $KVM_DIR/user_data-all $KVM_DIR/user_data
        virt-copy-in -a $KVM_DIR/all.qcow2 $KVM_DIR/user_data  /userdatas/openstack/latest/

        #vm onboot auto-start
        virsh autostart all

    else
        echo "Kvm image(centos7.1-FlexBNG-common-v1.0.qcow2) not exist!"
        exit 1
    fi

}

function show_help()
{
  cat <<EOF
Usage:
------------------------------------------------------------

To display current device status:
        ./flexbng_install.sh --status

To bind nic from the current driver and move to use vfi-pci,and create hugepage
        ./flexbng_install.sh --init 

To create the all-in-one vm
        ./flexbng_install.sh --create

Show help
        ./flexbng_install.sh --usage

-----------------------------------------------------------
EOF
}


if [ -z $action ];then 
    show_help
elif [ $action == "--status" ];then
    device_info
elif [ $action == "--init" ];then
#    system_check
    start_ovs
    device_info
    device_ovs_bind
    cpu_isolate
    hugepage
    bng_ovs_init
elif [ $action == "--create" ];then
    create_bng
elif [ $action == "--usage" ];then
     show_help
else
     show_help
fi
