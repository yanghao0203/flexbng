#!/bin/bash
##############################################################
# File Name: flexbng_install.sh
# Version: V1.0
# Author: yangh
# Organization: certusnet
# Created Time : 2017-09-14
# Description:  CP+DP FlexBNG installation
##############################################################
action=$1
device_name=()
DOWNLOAD_DIR=/tmp/flexbng
VBRAS_DIR=/home/vBras
KVM_DIR=$VBRAS_DIR/kvm-imgs

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

function start_ovs()
{
   mkdir -p $VBRAS_DIR
   mkdir -p $KVM_DIR
   cp -vaf Step*.sh $VBRAS_DIR
   chmod +x $VBRAS_DIR/*.sh
   echo "Start openvswitch"
   $VBRAS_DIR/Step1.start-ovs.sh
}

function cpu_info()
{
   echo "-----------------------------------CPU Info-----------------------------------------"
   numactl --hardware |grep cpu
}

function mem_info()
{
   echo "-----------------------------------MEM Info-----------------------------------------"
   numactl --hardware |grep size
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
               echo "-----------------------------------NIC Info------------------------------------------"
               echo "slot:      "$device
               echo "ifname:    "$ifname
               echo "mac:       "$mac
               echo "NUMA node: "$numa_node
               echo "Device:   "$device_mode
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

function device_bind()
{
   new_driver="vfio-pci"
   rm -rf .device_mac && touch .device_mac
   rm -rf .numa_node && touch .numa_node
   echo "id   ifname   slot  numa_node"
   for j in "${device_name[@]}" ; do
       temp=($j)
       echo [${temp[0]}]: ${temp[1]}"   "${temp[2]}"   " ${temp[4]}
   done
   echo -n "Choose the device:"
   read -a id
   if [ -z $id ]; then 
      echo "Please input device id."
      exit
   fi
   for i in "${id[@]}" ; do
      #echo "i="$i 
      for j in "${device_name[@]}" ;do
         temp=($j)
         #echo "test point1"
         #echo ${temp[@]}
         if [ "$i" == "${temp[0]}" ] ; then
             #echo "test point2"
             temp1=`echo ${temp[2]} | awk -F: '{print $2":"$3}'`
             #echo "temp1:"$temp1
             slot_id=${slot_id}" "$temp1
             bus=`echo $temp1 | awk -F: '{print $1}'`
             slot=`echo $temp1 | awk -F: '{print $2}' | awk -F. '{print $1}' `
             function=`echo $temp1 | awk -F: '{print $2}' | awk -F. '{print $2}' `
             touch ${temp[1]}_device.xml
             cat > ${temp[1]}_device.xml <<EOF
<hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
         <address domain='0x000' bus='0x$bus' slot='0x$slot' function='0x$function' />
      </source>
</hostdev>
EOF
            echo ${temp[3]} >> .device_mac
            echo ${temp[4]} > .numa_node
            
         fi
       done
    done

   echo -n "slot number is :"
   echo $slot_id
   
   echo "add new driver: $new_driver"
   echo "8086 10fb" > /sys/bus/pci/drivers/$new_driver/new_id
   for dev in $slot_id; do
           full_dev=0000:$dev
           echo "bind $full_dev to $new_driver"
           echo $full_dev > /sys/bus/pci/devices/$full_dev/driver/unbind 
           echo $full_dev > /sys/bus/pci/drivers/$new_driver/bind
           sleep 1
           
   done
   
}

function cpu_isolate()
{
    numa_node=`cat .numa_node`
    if [ -z $numa_node ];then
       echo "no numa config file exist."
       exit
    elif [ $numa_node == -1 ];then 
       numa_node=0
       temp_list=`numactl --hardware | grep "node $numa_node cpus" | awk -F: '{print $2}'`
    else 
       temp_list=`numactl --hardware | grep "node $numa_node cpus" | awk -F: '{print $2}'`
    fi
    echo "Current cpu list:"
    echo $temp_list
    #echo  -n  "Choose the cpu you want to isolate:"
    #read temp1_list

    for i in ${temp_list[@]};do
       if [ -z $cpu_list ];then
          cpu_list=$i
       else
          cpu_list=$cpu_list","$i
       fi
     done
    echo "cpu list will be isolated:"
    echo $cpu_list
    sed -i "s/115200n8/& isolcpus=$cpu_list/g" /etc/default/grub
}

function hugepage()
{
   numa_node=`cat .numa_node`
   if [ -z $numa_node ];then
     echo "no numa config file exist."
     exit
     
   elif [ $numa_node = 0 ];then
     #echo "Input hugepage size:"
     #read size
     #if [ -z $size ];then 
     #   echo "Please input hugepage size !!"    
     echo 20 > /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages
     echo 0 > /sys/devices/system/node/node1/hugepages/hugepages-1048576kB/nr_hugepages
     sed -i -e '/reset/a\echo 20 > /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages\necho 0 > /sys/devices/system/node/node1/hugepages/hugepages-1048576kB/nr_hugepages' $VBRAS_DIR/Step1.start-ovs.sh
     sed -i "s/hugepages=8/hugepages=20/g" /etc/default/grub
     grub2-mkconfig -o /boot/grub2/grub.cfg

     
   else
     echo 0 > /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages
     echo 20 > /sys/devices/system/node/node1/hugepages/hugepages-1048576kB/nr_hugepages
     sed -i -e '/reset/a\echo 0 > /sys/devices/system/node/node0/hugepages/hugepages-1048576kB/nr_hugepages\necho 20 > /sys/devices/system/node/node1/hugepages/hugepages-1048576kB/nr_hugepages' $VBRAS_DIR/Step1.start-ovs.sh
     sed -i "s/hugepages=8/hugepages=20/g" /etc/default/grub
     grub2-mkconfig -o /boot/grub2/grub.cfg

   fi
   mkdir -p /dev/hugepages1G
   mount -t hugetlbfs -o pagesize=1G none /dev/hugepages1G
}

function bng_init()
{
   numa_node=`cat .numa_node`
   echo "Add device to dp.xml..."
   devicefile=`find ./ -name "*_device.xml" | awk -F/ '{print $NF}' | sort`
   touch device_file
   echo ${devicefile[@]}
   for file in ${devicefile[@]}; do
   #  echo $file
     cat $file >> device_file 
   done
   sed -i 's/^/        /g' device_file
   sed -i '/<serial/i\ temp' dp.xml
   sed -i '/temp/r device_file' dp.xml
   sed -i '/temp/d' dp.xml
   sed -i 's/nodeset="0"/nodeset="'$numa_node'"/g' dp.xml
   dos2unix dp.xml
   rm -rf device_file
   
   echo "Add device to dp user_data"
   rm -rf user_data_temp && touch user_data_temp
   i=0
   for mac in `cat .device_mac`;do
      echo $mac
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

    sed -i 's/^/            /g' user_data_temp
    sed -i '/<network_interfaces/r user_data_temp' user_data-dp
    j=`grep "seq_id" user_data-dp | wc -l`
    for ((i=2;i<=j;i++));do
      a=`expr $i - 2`
      sed -i "/<seq_id>.*/{x;s/^/./;/^\.\{$i\}$/{x;s/.*/                <seq_id>$a<\/seq_id>/;x};x;}" user_data-dp
    done
    
    rm -rf user_data_temp
}

function bng_create()
{
    cd $DOWNLOAD_DIR
    # kvm image configure
    if [ -e centos7.1-FlexBNG-common-v1.0.qcow2 ];then
        chmod 755 centos7.1-FlexBNG-common-v1.0.qcow2
        cp -vaf centos7.1-FlexBNG-common-v1.0.qcow2 $KVM_DIR/cp.qcow2
        cp -vaf centos7.1-FlexBNG-common-v1.0.qcow2 $KVM_DIR/dp.qcow2

        # user_data backup file
        cp -vaf user_data-cp $KVM_DIR
        cp -vaf user_data-dp $KVM_DIR

        # user_data image
        #cp -vaf cp-data.img $KVM_DIR
        #cp -vaf dp-data.img $KVM_DIR

        # virsh xml
        cp -vaf cp.xml $KVM_DIR
        cp -vaf dp.xml $KVM_DIR

        #create vm
        virsh define $KVM_DIR/cp.xml
        virsh define $KVM_DIR/dp.xml

        #copy user-data to cp
        cp -vaf $KVM_DIR/user_data-cp $KVM_DIR/user_data
        virt-copy-in -a $KVM_DIR/cp.qcow2 $KVM_DIR/user_data  /userdatas/openstack/latest/
        cp -vaf $KVM_DIR/user_data-dp $KVM_DIR/user_data
        virt-copy-in -a $KVM_DIR/dp.qcow2 $KVM_DIR/user_data  /userdatas/openstack/latest/

        #vm onboot auto-start
        virsh autostart cp
        virsh autostart dp
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

./flexbng_install.sh --status            To display current cpu,mem,nic status.

./flexbng_install.sh --init              To bind nic to vfi-pci driver,cpu isolate,modify vm xml file and user_data file.

./flexbng_install.sh --create            To create and config new flexbng,before execute this step,you need to execute the init step.

./install_install.sh --help              Show help.

-----------------------------------------------------------
EOF
}


if [ -z $action ];then 
    show_help
    cpu_isolate
elif [ $action == "--status" ];then
    cpu_info
    mem_info
    device_info
    #system_check
elif [ $action == "--init" ];then
#    system_check
    start_ovs
    device_info
    device_bind
    cpu_isolate
    hugepage
    bng_init
elif [ $action == "--create" ];then
    bng_create
elif [ $action == "--help" ];then
    show_help
else
    show_help
fi

