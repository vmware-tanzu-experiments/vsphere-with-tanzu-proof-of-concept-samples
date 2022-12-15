# Creating Test VMs
Here we demonstrate how to quickly create a set of identical VMs for testing.<br>
For a more verbose procedure, visit Myles Gray’s blog: 
https://blah.cloud/infrastructure/using-cloud-init-for-vm-templating-on-vsphere

## Requirements:
•	FreeBSD, Linux or MacOS VM/host environment<br>
•	Latest version of govc (download instructions below)

## Download govc:
Govc is a lightweight, open-source CLI tool written in Go (and part of the Govmomi/Go library for the vSphere API). Project page: https://github.com/vmware/govmomi/tree/master/govc
To download the latest release, use the command below. As with the majority of Go projects, it is packaged as a single binary (note that the tar command requires root privileges to copy the binary to the correct location):
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | tar -C /usr/local/bin -xvzf - govc

## Connecting to vCenter
To authenticate with vCenter, we need to define the username, password and URL, as per the example below:
``` 
export GOVC_USERNAME=administrator@vsphere.local 
export GOVC_PASSWORD=P@ssw0rd
export GOVC_INSECURE=1
export GOVC_URL=10.156.163.1 
```

Additionally, we will need to specify the default datastore and resource pool (we can define this as the default/top-level cluster, as per blow)for deploying our VMs:
```
export GOVC_DATASTORE=ESA-vsanDatastore
export GOVC_RESOURCE_POOL='vSAN ESA Cluster/Resources'
```

Finally test the connection to vCenter by issuing the command below, it should return with details:
```
govc about
FullName:     VMware vCenter Server 8.0.0 build-20519528
Name:         VMware vCenter Server
Vendor:       VMware, Inc.
Version:      8.0.0
Build:        20519528
...
```


## Configure Test VM
First, specify a location of an OVA file to use. In the example below, we use an Ubuntu 22.04 cloud image:

`export vmLocation=https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.ova`


We can then add our customizations, etc. by extracting the JSON from the OVA:

`govc import.spec $vmLocation > ubuntu-vm.json`


buntu uses cloud-init to setup the OS. As we will be cloning the deployed VM, we need to define specific user-data (which will be encoded in base-64 and added to the customization JSON). Here we modify the default netplan config file to ensure DHCP addresses are assigned by mac address.
To simplify the process, the user-data file can be downloaded from the link below:
https://raw.githubusercontent.com/vmware-tanzu-experiments/vsphere-with-tanzu-proof-of-concept-samples/main/VCF/test_vms/user-data

If available, use cloud-init to check the user-data file:

`cloud-init schema --config-file user-data`


Next, we encode the user-data to base64:
```
base64 -i user-data
I2Nsb3VkLWNvbmZpZwpydW5jbWQ6CiAgLSAnZWNobyAiZGlzYWJsZV92bXdhcmVfY3VzdG9taXphdGlvbjogZmFsc2UiID4+IC9ldGMvY2xvdWQvY2xvdWQuY2ZnJwogIC0gZWNobyAtbiA+IC9ldGMvbWFjaGluZS1pZAogIC0gfAogICAgc2VkIC1pICcnIC1lICdzL21hdGNoLiovZGhjcC1pZGVudGlmaWVyOiBtYWMvZycgLWUgJy9tYWMvcScgL2V0Yy9uZXRwbGFuLzUwLWNsb3VkLWluaXQueWFtbApmaW5hbF9tZXNzYWdlOiAiVGhlIHN5c3RlbSBpcyBwcmVwcGVkLCBhZnRlciAkVVBUSU1FIHNlY29uZHMiCnBvd2VyX3N0YXRlOgogIHRpbWVvdXQ6IDMwCiAgbW9kZTogcG93ZXJvZmYK
```

Now we can edit the JSON file we extracted earlier. Change the file with the following:
•	Disk provisioning set to ‘thin’
•	Add the public key of the machine we are connecting from
•	Remove the hostname and password data
•	Set the network for the VM (the name of the relevant portgroup in vCenter)
•	Set the name of the VM
•	In the ‘user-data’ section, paste in the  base64 encoded data

An example of this file can be seen here:
https://raw.githubusercontent.com/vmware-tanzu-experiments/vsphere-with-tanzu-proof-of-concept-samples/main/VCF/test_vms/ubuntu-vm.json


Once this JSON file has been defined, we can double-check our user-data encoding is still correct:

`awk -F '"' '/user-data/{ getline; print $4}' ubuntu-vm.json | base64 -d`


This should return the user-data as we defined above.

## Import OVA to vCenter and Clone
We can then import the OVA into vCenter, specifying our JSON customization file:

`govc import.ova -options=ubuntu-vm.json -name=ubuntu-vm $vmLocation`


After this has imported, we can update the virtual disk size. Here we set it to 100G:

`govc vm.disk.change -vm ubuntu-vm -disk.label "Hard disk 1" -size 100G`


Power on the VM to allow it to run cloud-init (and thus our previously defined commands). Once complete, the VM will shutdown:

`govc vm.power -on ubuntu-vm`


Once the VM has shutdown, mark it as a template:

`govc vm.markastemplate ubuntu-vm`


Finally, we can clone our template VM as we need to. In the example below, we clone it ten times:

`for x in {1..10};do govc vm.clone -vm ubuntu-vm ubuntu-vm$x;done`
