#!/bin/bash

# Used to turn on/off vCLS RETREAT mode
# to tell vC to remove / re-create vCLS VMs
# REQUIRES GOVC



# check the input args

if [[ $# -lt 2 ]]
  then
    echo "Usage: vCLS.sh <Cluster Name> <enable|disable> "
    exit
elif [[ $2 != 'disable' ]] && [[ $2 != 'enable' ]]
  then
    echo "Usage: vCLS.sh <Cluster Name> <enable|disable> "
    exit
fi



# Check for govc
# (verbose redirect for max. compat.)
echo -n Checking for govc... 

if govc version 2>/dev/null 1>/dev/null
then 
	echo govc found
else
	echo No govc command found... you can find it here:
	echo https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz
	exit
fi


# check for vC access rights
echo -n Checking for vC access...

if 
	govc about 2>/dev/null | grep 'Version' 
then
	echo
else
	echo Failed!
	echo
	echo You need to set govc env variables, e.g.:
	echo
	echo export GOVC_USERNAME=administrator@vsphere.local
	echo export GOVC_PASSWORD=your_vcenter_password
	echo export GOVC_INSECURE=1
	echo export GOVC_URL=your_vcenter_ip_address
	exit
fi




cluster=$1

# make sure the cluster exists

echo -n Checking for cluster...

if govc find -type c | grep $cluster 2>/dev/null
then
	echo \>\>found cluster $cluster
else
	echo Failed!
	echo Please check the cluster name
	echo Available clusters are:
	govc find -type c | awk -F'/' '{print $NF}'
	exit
fi


echo Setting vCLS state in $cluster to $2
domain=$(govc find -verbose=true -type c 2> >(grep $cluster) | grep -oEm 1 'domain-c\w+')

echo \>\>found domain $domain
	
# Do the thing 

if [[ $2 -eq 'disable' ]]
then
	govc option.set config.vcls.clusters.$domain.enabled false
elif [[ $2 -eq 'enable' ]]
then
	govc option.set config.vcls.clusters.$domain.enabled true
else
	echo Hmmm...something went wrong, sorry
	exit
fi

if [[ $(echo $?) -eq 0 ]]
then echo Done!
else echo Sorry, something went wrong
fi


