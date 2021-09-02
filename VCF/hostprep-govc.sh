#!/bin/bash
 
### govc/VC params: input esxi credentials
export GOVC_USERNAME=root
export GOVC_PASSWORD=P@ssw0rd
export GOVC_INSECURE=1
 
 
### variables: change as needed
START_IP=10.156.176.10
NUM_HOSTS=4
GATEWAY=10.156.176.1
DNS_SERVER=10.156.176.1
NTP_SERVER=10.156.176.1
MGMT_VLAN=1284
VSWITCH=vSwitch0
 
####
# evaluate loop bounds
a=${START_IP##*.}
b=$(($a + $NUM_HOSTS - 1))
PREFIX=${START_IP%.*}"."
 
printf "Setting up hosts."
# loop through all hosts, applying settings, etc.
for x in $(seq $a $b)
do
 govc host.service -u=$PREFIX$x enable ntpd
 govc host.service -u=$PREFIX$x enable TSM-SSH
 govc host.date.change -u=$PREFIX$x -server $NTP_SERVER
 govc host.esxcli -u=$PREFIX$x network ip dns server add -s=$DNS_SERVER
 govc host.esxcli -u=$PREFIX$x network ip route ipv4 add -g=$GATEWAY -n=default
 govc host.option.set -u=$PREFIX$x UserVars.SuppressShellWarning 1
 govc host.portgroup.change -u=$PREFIX$x -vlan-id=$MGMT_VLAN "VM Network"
 govc host.service -u=$PREFIX$x start ntpd
 govc host.service -u=$PREFIX$x start TSM-SSH
 govc host.esxcli -u=$PREFIX$x network vswitch standard set -v $VSWITCH -m 9000
 h=$(dig -x $PREFIX$x @$DNS_SERVER +short); h=${h%.}
 govc host.esxcli -u=$PREFIX$x system hostname set -f $h
 
 printf "."
 
 # regen the certs ... ** REQUIRES SSHPASS **
 certCheck=$(sshpass -p "$GOVC_PASSWORD" ssh -o StrictHostKeyChecking=no "$GOVC_USERNAME"@$PREFIX$x '/sbin/generate-certificates' &>/dev/null)$!
 wait $certCheck
     
 
 # restart services
 servicesCheck=$(sshpass -p "$GOVC_PASSWORD" ssh -o StrictHostKeyChecking=no "$GOVC_USERNAME"@$PREFIX$x '/bin/services.sh restart' &>/dev/null)$!
 wait $servicesCheck
 
 
 printf "."
done
 
 
printf "OK"