#!/bin/bash

####
# Wrapper script to easily turn on/off vCLS RETREAT mode
# -to tell vCenter to remove / re-create vCLS VMs
#
# Download govc: https://github.com/vmware/govmomi/releases
# 
# Author: Dharmesh Bhatt
####


usage() 
{
	printf "Enable or disable the vCLS VMs in a cluster (vCLS Retreat Mode)\nSets an advanced parameter in vCenter\nUses govc (https://github.com/vmware/govmomi/tree/master/govc)\n\n" 
	printf "$0 -c 'cluster name' -s [enable|disable]\n\n"
	exit 1
}

cluster_fail()
{
	printf "Failed!\n\nPlease check the cluster name\nAvailable clusters are:\n\n"
	govc find -type c | awk -F'/' '{print "\"" $NF  "\""}'
	echo
	exit 1
}

vc_fail()
{
    printf "Failed!\n\nYou need to set govc env variables, e.g.:\n\n"
	printf "export GOVC_USERNAME=administrator@vsphere.local\nexport GOVC_PASSWORD=your_vcenter_password\nexport GOVC_INSECURE=1\nexport GOVC_URL=your_vcenter_ip_address\n\n"
	exit 1
}

govc_fail() { printf "No govc command found...\nYou can download it here:\nhttps://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz\n\n" && exit 1; }

undefined_error() { printf "Hmmm...something went wrong, sorry\n" && exit 1; }

set_vcls() { govc option.set config.vcls.clusters.$domain.enabled $1 && return $?; }

end() { ([[ $(echo $1) -eq 0 ]] && echo Done! || undefined_error) && exit $1; }


# process the input args

! [[ ${#} -eq 4 ]] && usage
while getopts ":c:s:" options; do
  case "${options}" in
    c)
      cluster=${OPTARG}
      ;;
    s)
      state=${OPTARG}
      ! [[ ($state == 'disable') || ($state == 'enable') ]] && usage
      ;;
    :)
      echo "Error: -${OPTARG} requires an argument."
      usage
      ;;
    *)
      usage
      ;;
  esac
done



# Check for govc
printf "Checking for govc..." 
[[ $(govc version) ]] && echo OK || govc_fail

# check for vC access rights
printf "Checking for vC access..."
[[ $(govc about 2>/dev/null | grep 'Version') ]] && echo OK || vc_fail

# make sure the cluster exists
printf "Checking for Cluster..."
[[ $(govc find -type c | grep -oE "\<$cluster\$") ]] && echo OK || cluster_fail
echo Setting vCLS state in $cluster to $state

# find the domain
domain=$(govc find -verbose=true -type c 2> >(grep -E "\<$cluster\$") | grep -oEm 1 'domain-c\w+')
[[ $(echo $?) -eq 0 ]] && echo \>\>Cluster $cluster translates to MOB object $domain || undefined_error
	
# Do the thing 
[[ "$state" == "disable" ]] && set_vcls "false" && end $? || [[ "$state" == "enable" ]] && set_vcls "true" && end $?

# Catch anything else
undefined_error
exit 1


