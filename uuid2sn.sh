#!/bin/bash
action=$1
para=$2
sn=$(awk -F"\"" 'NR==2{print $6}' /userdatas/openstack/latest/user_data)

function show_help {
  cat <<EOF
  Usage:
  ------------------------------------------------------------

  ./uuid2sn.sh -d            Display the sn number.

  ./uuid2sn.sh -c            Create new sn number.If sn number is already is exist,display the current sn number.

  ./uuid2sn.sh -c  -f        Create new sn number no matter the sn is already exist or not.

  ./uuid2sn.sh -h/--help     Show help.

  -----------------------------------------------------------
EOF
}

if [ -z $action ];then
    show_help
elif [ $action == "-c" ];then
  if [ -z $para ]; then
    if [ -z $sn ];then
       #sn=$(cat /proc/sys/kernel/random/uuid | sed 's/-//g')
       sn=$(cat /proc/sys/kernel/random/uuid | sed 's/-//g' |head -c 16 | tr '[a-z]' '[A-Z]')
       echo "The new SN number of this Edge is $sn"
       sed -i "s/parentid=\".*\"/& parentuuid=\"$sn\"/" /userdatas/openstack/latest/user_data
       #sed -i "s/parentid=\".*\"/& parentuuid=\"$sn\"/" user_data-dp
    else
       echo "The SN number of this Edge is $sn"
    fi
  elif [ $para = "-f" ];then
    echo "Renew the SN number of this Edge..."
    echo "The old SN number of this Edge is $sn"
    sn=$(cat /proc/sys/kernel/random/uuid | sed 's/-//g' |head -c 16 | tr '[a-z]' '[A-Z]')
    echo "The new SN number of this Edge is $sn"
    sed -i "s/parentid=\".*\"/parentuuid=\"$sn\"/" /userdatas/openstack/latest/user_data
  else
   echo "Please input the correct parameter."
  fi
elif [ $action == "-d" ];then
    if [ -z $sn ];then
      echo "SN number is not exist.Please create it."
    else
      echo "The SN number of this Edge is $sn"
    fi
elif [ $action == "--help" ];then
    show_help
elif [ $action == "-h" ];then
    show_help
else
    echo "Please input correct parameter."
    show_help
fi
