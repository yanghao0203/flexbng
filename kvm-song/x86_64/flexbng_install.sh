#!/bin/bash
##############################################################
# File Name: flexbng_install.sh
# Version: V1.0
# Author: yangh
# Organization: netElastic
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
   echo -n "Check CPU model..."


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
   echo "Start openvswitch and libvirt..."
   mkdir -p $VBRAS_DIR
   mkdir -p $KVM_DIR
   cp -vaf Step*.sh $VBRAS_DIR
   chmod +x $VBRAS_DIR/*.sh
   echo "Start openvswitch"
   $VBRAS_DIR/Step1.start-ovs.sh
   systemctl enable flexbng.service
   systemctl enable libvirtd.service
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
           vendor=`cat /sys/bus/pci/drivers/$driver/$device/vendor | awk -Fx '{print $2}'`
           device_id=`cat /sys/bus/pci/drivers/$driver/$device/device | awk -Fx '{print $2}'`
           if [ -z $action ];then
              action=default
           elif [ $action == "--status" ];then
               echo "-----------------------------------NIC Info------------------------------------------"
               echo "slot:      "$device
               echo "ifname:    "$ifname
               echo "mac:       "$mac
               echo "NUMA node: "$numa_node
               echo "Device:    "$device_mode
               echo "Vendor:    "$vendor
               echo "Device_id: "$device_id
           fi
           temp[0]=$i
           temp[1]=$ifname
           temp[2]=$device
           temp[3]=$mac
           temp[4]=$numa_node
           temp[5]=$vendor
           temp[6]=$device_id
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
   rm -rf .vendor && touch .vendor
   echo "id   ifname   slot  numa_node   vendor:device_id"
   for j in "${device_name[@]}" ; do
       temp=($j)
       echo [${temp[0]}]: ${temp[1]}"   "${temp[2]}"   "${temp[4]}"    "${temp[5]}:${temp[6]}
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
             rm -rf /etc/sysconfig/network-scripts/ifcfg-${temp[1]}
             cat > ${temp[1]}_device.xml <<EOF
<hostdev mode='subsystem' type='pci' managed='yes'>
      <source>
         <address domain='0x000' bus='0x$bus' slot='0x$slot' function='0x$function' />
      </source>
</hostdev>
EOF
            echo ${temp[3]} >> .device_mac
            echo ${temp[4]} > .numa_node
            echo "${temp[5]}:${temp[6]}" >> .vendor

         fi
       done
    done

   echo -n "slot number is :"
   echo $slot_id

   echo "add new driver: $new_driver"
   vendor_list=`cat .vendor | sort -u`
   for vendor_temp in $vendor_list; do
       vendor_temp=${vendor_temp//:/ }
       echo $vendor_temp > /sys/bus/pci/drivers/$new_driver/new_id
   done
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
    echo "Begain cpu isolation..."
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
   echo "Setting bugepage..."
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
    echo "Create CP and DP vms..."
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

function version_install()
{
   if [ ! -d /var/www/html/flexbng ];then
      mkdir /var/www/html/flexbng
      cp $DOWNLOAD_DIR/song* /var/www/html/flexbng
       echo "Starting http server..."
      service httpd restart
      systemctl enable httpd.service
   fi

   echo "Check the status of CP and DP vms..."
   cp_status=`virsh list |grep cp | awk '{print $3}'`
   dp_status=`virsh list |grep dp | awk  '{print $3}'`
   if [ -z $cp_status ] && [ -z $dp_status ] ;then
     echo " CP and DP are not running.Starting... "
     virsh start cp
     virsh start dp
     sleep 15
   elif [ -z $cp_status ] ;then
     echo "CP is not running.Starting..."
     virsh start cp
     sleep 10
   elif [ -z $dp_status ] ;then
     echo "DP is not running.Starting..."
     virsh start dp
     sleep 15
   else
      echo "CP and DP are all running."
   fi

   i=1
   version_list=()
   current_version=`curl -s -X GET "http://192.169.1.101:9098/v1/vnf/version" | tr -d '"' | awk -F, '{print $7}' | awk -F: '{print $2}'`
   echo "Begain install flexbng version..."
   for temp in `ls /var/www/html/flexbng/`;do
      if [ -z $temp ];then
        echo "These is no version under /var/www/html/flexbng,Please upload version."
        exit
      else
        echo [$i]:$temp
        version_list[$i]=$temp
        i=`expr $i + 1`
      fi
   done

   #echo $number
   while true; do
      len=${#version_list[@]}
      if [ $len = 1 ];then
         update_version=`echo ${version_list[1]} | awk -F. '{print $1}'`
         break
      else
        echo -n "Choose the version:"
        read number
        if [ -z $number ] || [ $number -ge $i ] ;then
          echo "Pls input the correct version number!"
          continue
        else
          update_version=`echo ${version_list[$number]} | awk -F. '{print $1}'`
          break
        fi
      fi
   done

   FileUrl=http://192.169.1.1/flexbng/$update_version.all.tar.gz
   md5_value=`md5sum /var/www/html/flexbng/$update_version.all.tar.gz | awk '{print $1}'`

   while true; do
      if [ -z $current_version ];then
        curl http://192.169.1.101:9098/v1/vnf/version -X POST -i -H "Content-Type:application/json" -d '{"FileUrl": "'"$FileUrl"'", "Version": "'"$update_version"'", "Md5": "'"$md5_value"'"}'
      elif [ $update_version == $current_version ];then
        echo -n "The new version is same as the current version.Still installed?[no/yes]:"
        read answer
        if [ $answer = y ] || [ $answer = yes ];then
          echo "Stop the flexbng processes"
          curl -X POST "http://192.169.1.101:9098/v1/vnf/app?action=stop"
          sleep 5
          echo "Install new version"
          curl http://192.169.1.101:9098/v1/vnf/version -X POST -i -H "Content-Type:application/json" -d '{"FileUrl": "'"$FileUrl"'", "Version": "'"$update_version"'", "Md5": "'"$md5_value"'"}'
          break
        elif [ $answer = n ] || [ $answer = no ];then
          echo "Cancel install."
          exit
        else
         echo "Please input yes or no."
         continue
        fi
      else
       echo -n "Stop the flexbng processes..."
       curl -X POST "http://192.169.1.101:9098/v1/vnf/app?action=stop"
       sleep 5
       echo "Done."
       echo -n "Install new version..."
          curl http://192.169.1.101:9098/v1/vnf/version -s -X POST -i -H "Content-Type:application/json" -d '{"FileUrl": "'"$FileUrl"'", "Version": "'"$update_version"'", "Md5": "'"$md5_value"'"}'
       break
      fi
   done

   #version install status check
   while true; do
      cp_status=`curl -s -X GET "http://192.169.1.101:9098/v1/vnf/version" | tr -d '"' | awk -F, '{print $14}' | awk -F: '{print $2}'`
      dp_status=`curl -s -X GET "http://192.169.1.101:9098/v1/vnf/version" | tr -d '"' | awk -F, '{print $29}' | awk -F: '{print $2}'`
      if [ "$cp_status" = "807" ] || [ "$dp_status" = "807" ]; then
        echo "Version deploying is failed.Please check the vms status."
        break
      elif [ "$cp_status" = "805" ] || [ "$dp_status" = "805" ]; then
        sleep 1
        echo -n "..."
        continue
      else
        echo "Done."
        break
      fi
    done
}

function reboot_system()
{
  while true; do
     echo -n "Need to reboot the server to make CPU isolation effective.Reboot now?[yes/no]"
     read answer
     if [ -z $answer ] || [ $answer = y ] || [ $answer = yes ];then
        shutdown -r now
        break
     elif [ $answer = n ] || [ $answer = no ];then
        echo "Please reboot the server manually later."
        exit
     else
        echo "Please input yes/y or no/n."
        continue
     fi
  done
}

function show_help()
{
  cat <<EOF
Usage:
------------------------------------------------------------

./flexbng_install.sh --status            To display current cpu,mem,nic status.

./flexbng_install.sh --init              To bind nic to vfi-pci driver,cpu isolate,modify vm xml file and user_data file.

./flexbng_install.sh --create            To create and config new flexbng,before execute this step,you need to execute the init step.

./flexbng_install.sh --deploy            To deploy flexbng version.

./flexbng_install.sh --all               To init the envirement,create vms and deploy new version.

./install_install.sh --help              Show help.

-----------------------------------------------------------
EOF
}


if [ -z $action ];then
    show_help
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
elif [ $action == "--deploy" ];then
    version_install
elif [ $action == "--all" ];then
    start_ovs
    device_info
    device_bind
    cpu_isolate
    hugepage
    bng_init
    bng_create
    version_install
    reboot_system
elif [ $action == "--help" ];then
    show_help
else
    show_help
fi
