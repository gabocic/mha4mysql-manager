#!/bin/bash

ARGV="$@"

#Customize the values below to match your environment

BINHOME=/usr/bin
SBINHOME=/sbin
SSH_USER=super
ISSUDO=""
PARENTDEVICE=eth0
VDEVICE=":0"
VIP="172.16.0.111"
NETMASK='255.255.255.0'
HOST='127.0.0.1'
KILL_TIMEOUT=1
VERBOSE=0
ARPING=/usr/sbin/arping

# Local interfase used by arping to update neighbours' ARP caches
LOCALIF="eth0"

# 3 methods start/stop/check
# Start will check for vip already on the net if yes will exit with error (code 1)
# if not will start virtual ip on define device
#
# Stop will check for vip and will try to stop device
# check again if still up will exit with error otherwise code OK (code 0)
#
# Check will check for vip and will check for VIP on the current machine if match will report ok otherwise error
#
# Customize
# parent device IE eth1
# virtual device IE eth1:1
# VIP
# if sudo is required
# I also clean up the ARP map table to be sure

#
# Use LSB init script functions for printing messages, if possible
#
log_success_msg=" [ \e[32mOK\e[39m ] \n"
#"/etc/redhat-lsb/lsb_log_message success"
log_failure_msg=" [ \e[91mERROR\e[39m ] \n"
#"/etc/redhat-lsb/lsb_log_message failure"
log_warning_msg=" [ \e[93mWARNING\e[39m ] \n"
#"/etc/redhat-lsb/lsb_log_message warning"

usage() {
echo "Valid commands are start|stop|check [-h host] [-i vip] [-s (sudo)] [-v (verbose)i] [-n (netmask)] [-]"
echo "vipmanager_mt.sh start -h <host_ip> -i <vip>"
echo "vipmanager_mt.sh check -h <host_ip> -i <vip>"
echo "vipmanager_mt.sh stop -h <host_ip> -i <vip>"
}

if [ $# -lt 1 ] ; then
        echo 'Too few arguments supplied'
        usage
        exit 1
fi

ACTION=$1
shift 1

while getopts ":h:i:n:s:v" opt; do
  case $opt in
    h)
       HOST=$OPTARG

       if [ $VERBOSE -eq 1  ] ; then
           echo "Host is set to $HOST"
       fi
       ;;
    i)
       VIP=$OPTARG

       if [ $VERBOSE -eq 1  ] ; then
           echo "VIP is set to $VIP"
       fi
       ;;
    s)
       ISSUDO="sudo " #Note due to ssh usage, we need to comment out "Defaults    requiretty" in /etc/sudoers
       ;;
    v)
       VERBOSE=1
       ;;
    n)
       NETMASK=$OPTARG
       echo "Netmask is set to $NETMASK"
       ;;
    \?)
       echo "Invalid option: -$OPTARG" >&2
       exit 1
       ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

do_retry()
{
cmd="$1"
retry_times=$2
retry_wait=$3

c=0
while [ $c -lt $((retry_times+1)) ]; do
        c=$((c+1))
        if [ $VERBOSE -eq 1 ] ; then
                echo "Executing \"$cmd\", try $c"
        fi
        $1 && return $?
                if [ ! $c -eq $retry_times ]; then
                        if [ $VERBOSE -eq 1 ] ; then
                                echo "Command failed, will retry in $retry_wait secs"
                        fi
                        sleep $retry_wait
                else
                        if [ $VERBOSE -eq 1 ] ; then
                                echo "Command failed, giving up."
                        fi
                        return 1
                fi
done
}

ssh_command(){
        ssh $SSH_USER@$HOST "$1"
}

check_ifconfig(){
#echo "ssh $SSH_USER@$HOST "$SBINHOME/ifconfig" | grep $VIP"
        returnval=`ssh $SSH_USER@$HOST "$SBINHOME/ifconfig" | grep $VIP`
        echo $returnval
}

check_ip(){
            #ssh_command "$ISSUDO/$SBINHOME/arp -d $VIP"
            ssh_command "$BINHOME/nc -w 1 -v $VIP 22 < /dev/null"  > /dev/null 2>&1
            if [ $? -ne 0 ] ; then
              return 1
            else
              return 0
            fi
}

case $ACTION in
        start)
            check_ip
            if [ $? -ne 0 ] ; then
               if [ $VERBOSE -eq 1  ] ; then
                   printf "VIP $VIP not allocated going to create virtual device:$PARENTDEVICE$VDEVICE \n"
               fi
                #NETMASK=`/sbin/ifconfig $PARENTDEVICE | grep -i 'mask' | awk '{print $4}'| cut -d':' -f2`
                if [ $VERBOSE -eq 1  ] ; then
                        echo "Netmask = $NETMASK"
                fi
                ssh_command "$ISSUDO$SBINHOME/ifconfig $PARENTDEVICE$VDEVICE $VIP netmask $NETMASK"
                #checking if NOW we have the IP up
              do_retry check_ip 5 0
              if [ $? -ne 1 ] ; then
                if [ $VERBOSE -eq 1 ] ; then
                    printf "VIP $VIP NOW allocate on device:$PARENTDEVICE$VDEVICE\n"
                    #$ISSUDO$ARPING -c 2 -A -I $PARENTDEVICE $VIP
                    $ISSUDO$ARPING -c 2 -A -I $LOCALIF $VIP
                fi
                ifconfigchck=$(check_ifconfig)
                if [ x"$ifconfigchck" = "x" ]; then
                    if [ $VERBOSE -eq 1 ] ; then
                        echo "VIP $VIP was not able to be allocated on $HOST machine"
                        echo -en $log_failure_msg
                    fi
                                        echo "VIP $VIP was not able to be allocated on $HOST machine"
                    exit 1
                fi
                if [ $VERBOSE -eq 1 ] ; then
                    if [ $VERBOSE -eq 1 ] ; then
                        ping -c 3 -w 60 $VIP
                    else
                        ping -c 3 -w 60 $VIP > /dev/null
                    fi
                    echo "VIP at $VIP was added successfully"
                    echo -en $log_success_msg
                fi
                exit 0
              else
                if [ $VERBOSE -eq 1 ] ; then
                    printf "Not able to allocate VIP $VIP on device:$PARENTDEVICE$VDEVICE\n"
                    echo -en  $log_failure_msg
                fi
                echo "Not able to allocate VIP $VIP on device:$PARENTDEVICE$VDEVICE\n"
                exit 1
              fi
            else
                if [ $VERBOSE -eq 1 ] ; then
                    printf "Not able to allocate VIP $VIP on device:$PARENTDEVICE$VDEVICE \nIP already present on the network.\n"
                fi
                    exit 1
            fi

        ;;

# stop try to put down the virtual device
        stop)

            #check for IP on the net
            check_ip
            if [ $? -ne 0 ] ; then
                if [ $VERBOSE -eq 1 ] ; then
                    printf "VIP $VIP not allocated no need to remove it\n"
                    echo -en $log_success_msg
                fi
                exit 0
            else
                #trying to put Virtual device down
                #ssh_command "$BINHOME/ping -c 1 -w 2 $VIP"
                if [ $VERBOSE -eq 1 ] ; then
                        echo "Going to remove = $(check_ifconfig)"
                fi
                ssh_command "$ISSUDO$SBINHOME/ifconfig $PARENTDEVICE$VDEVICE down"
              do_retry check_ip 5 0
              if [ $? -ne 0 ] ; then
              if [ $VERBOSE -eq 1 ] ; then
                    ping -c 3 -w 60 $VIP
                else
                    ping -c 3 -w 60 $VIP > /dev/null
              fi
                if [ $VERBOSE -eq 1 ] ; then
                    $ISSUDO$ARPING -c 2 -I $PARENTDEVICE$VDEVICE -S $VIP -B
                    $ISSUDO$ARPING -c 2 -I $LOCALIF -S $VIP -B
                                        printf "VIP $VIP removed on device:$PARENTDEVICE$VDEVICE\n"
                                        echo -en $log_success_msg
                                        echo $(ssh_command "$ISSUDO/$SBINHOME/arp -d $VIP") > /dev/null
                                fi
                exit 0
              else

                # first check if the ip is present because not on the target machine
                #ifconfigchck=$(check_ifconfig)
                ifconfigchck=$(check_ip)
                #if [ x"$ifconfigchck" = "x" ]; then
                if [ $? -ne 0 ]; then
                    if [ $VERBOSE -eq 1 ] ; then
                        printf "VIP $VIP is not allocated to this machine but it still present on the network check which node is still using it"
                        echo -en $log_failure_msg
                    fi
                        echo "VIP $VIP is not allocated to this machine but it still present on the network check which node is still using it"
                    exit 1
                fi

                ifconfigchck=$(check_ifconfig)
                echo "Checking Machine ifconfig = "
                if [ x"$ifconfigchck" != "x" ]; then
                        if [ $VERBOSE -eq 1 ] ; then
                            printf "Device still allocate "$ifconfigchck
                            printf "Not able to remove VIP $VIP on device:$PARENTDEVICE$VDEVICE\n"
                         echo -en $log_failure_msg
                        fi
                                echo "Not able to remove VIP $VIP on device:$PARENTDEVICE$VDEVICE\n"
                        exit 1
                fi
                if [ $VERBOSE -eq 1 ] ; then
                        echo -en $log_success_msg
                fi
                exit 0
              fi
            fi
        ;;


    check)
            check_ip
            if [ $? -ne 0 ] ; then
                if [ $VERBOSE -eq 1 ] ; then
                    echo "VIP at $VIP is not working"
                    echo -en $log_failure_msg
                fi
              echo "VIP at $VIP is not working"
                  exit 1
            else
                #ssh_command "$BINHOME/ping -c 1 -w 2 $VIP"
                ifconfigchck=$(check_ifconfig)
                if [ x"$ifconfigchck" = "x" ]; then
                    if [ $VERBOSE -eq 1 ] ; then
                        echo "VIP $VIP is working but not on $HOST machine"
                        echo -en $log_failure_msg
                    fi
                        echo "VIP $VIP is working but not on $HOST machine"
                    exit 1
                fi
                if [ $VERBOSE -eq 1 ] ; then
                    echo "VIP at $VIP is correctly working"
                    echo -en $log_success_msg
                fi
              exit 0
            fi
    ;;

    help)
        usage

    ;;
*)
esac
