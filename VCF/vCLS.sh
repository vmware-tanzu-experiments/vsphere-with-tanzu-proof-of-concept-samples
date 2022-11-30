#!/bin/bash

# Used to turn on/off vCLS RETREAT mode
# to tell vC to remove / re-create vCLS VMs
# REQUIRES GOVC




usage() 
{
	echo Enable or disable the vCLS VMs in a cluster \(vCLS Retreat Mode\)
	echo Sets an advanced parameter in vCenter
	echo Uses govc \(https://github.com/vmware/govmomi/tree/master/govc\)
	echo 
	echo "$0  -c 'cluster name' -s [enable|disable]" 1>&2
	echo
	exit 1
}

cluster_fail()
{
	echo Failed!
	echo
	echo Please check the cluster name
	echo Available clusters are:
	echo
	govc find -type c | awk -F'/' '{print "\"" $NF  "\""}'
	echo
	exit 1
}


vc_fail()
{
    echo Failed!
	echo
	echo You need to set govc env variables, e.g.:
	echo
	echo export GOVC_USERNAME=administrator@vsphere.local
	echo export GOVC_PASSWORD=your_vcenter_password
	echo export GOVC_INSECURE=1
	echo export GOVC_URL=your_vcenter_ip_address
	echo
	exit 1
}

govc_fail()
{
    echo No govc command found... 
    echo You can download it here:
	echo https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz
	echo
	exit 1
}

undefined_error()
{
	echo Hmmm...something went wrong, sorry
	exit 1
}

set_vcls()
{
    govc option.set config.vcls.clusters.$domain.enabled $1
    return $?
}

end()
{
	[[ $(echo $1) -eq 0 ]] && echo Done! || undefined_error
	exit $1
}


# check the input args

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
echo -n Checking for govc... 
[[ $(govc version) ]] && echo OK || govc_fail

# check for vC access rights
echo -n Checking for vC access...
[[ $(govc about 2>/dev/null | grep 'Version') ]] && echo OK || vc_fail

# make sure the cluster exists
echo -n Checking for Cluster...
[[ $(govc find -type c | grep -oE "\<$cluster\$") ]] && echo OK || cluster_fail

# find the domain
echo Setting vCLS state in $cluster to $state
domain=$(govc find -verbose=true -type c 2> >(grep -E "\<$cluster\$") | grep -oEm 1 'domain-c\w+')
[[ $(echo $?) -eq 0 ]] && echo \>\>Cluster $cluster translates to MOB object $domain || undefined_error
	
# Do the thing 
[[ "$state" == "disable" ]] && set_vcls "false" && end $? || [[ "$state" == "enable" ]] && set_vcls "true" && end $?

# Catch anything else
end 1


