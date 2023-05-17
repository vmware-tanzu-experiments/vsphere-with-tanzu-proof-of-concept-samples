# Creating Test VMs
Here we demonstrate how to quickly create a set of identical VMs for testing.<br>
This is based (and extends) the procedure detailed in Myles Gray’s blog:<br> 
https://blah.cloud/infrastructure/using-cloud-init-for-vm-templating-on-vsphere

## Requirements:
•	FreeBSD, Linux or MacOS VM/host environment<br>
•	Latest version of `govc` (download instructions below) <br>
• `jq` is highly recommended to avoid hand-editing <br> 
•	vSphere Portgroup with DHCP to deploy the worker VMs

## Download govc:
[govc](https://github.com/vmware/govmomi/tree/master/govc) is a lightweight, open-source CLI tool written in Go (and part of the Govmomi/Go library for the vSphere API). Project page: <br>

To download the latest release, use the command below. As with the majority of Go projects, it is packaged as a single binary.<br>
Note that the tar command requires **root privileges** to copy the binary to the correct location):

```bash 
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | tar -C /usr/local/bin -xvzf - govc
```

## Connecting to vCenter
To authenticate with vCenter, we need to define the username, password and URL, as per the example below:
``` 
export GOVC_USERNAME=administrator@vsphere.local 
export GOVC_PASSWORD=myVCpassword
export GOVC_INSECURE=1
export GOVC_URL=192.150.16.1 
```

Additionally, we will need to specify the default datastore and resource pool (we can define this as the default/top-level cluster, as per blow) for deploying our VMs:
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

### Get the VM image JSON file
First, specify a location of an OVA file to use. In the example below, we use an Ubuntu 22.04 cloud image:

```
export vmLocation=https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.ova
```


We can then add our customizations, etc. by extracting the JSON from the OVA:

```
govc import.spec $vmLocation > ubuntu-vm.json
```

### Customise the VM image JSON file

#### User-data file

First, we need a user-data file to pass into cloud-init.

(This file tells cloud-init not to disable vSphere specific configurationd, and we modify the default netplan config file to ensure DHCP addresses are assigned by mac address.)

An example user-data file can be direcly downloaded using curl
```
curl -o user-data -sk https://raw.githubusercontent.com/vmware-tanzu-experiments/vsphere-with-tanzu-proof-of-concept-samples/main/VCF/test_vms/user-data
```

<details>
  <summary> 
  Example user-data file (for reference): 
  </summary>
  
  ```
  #cloud-config
runcmd:
  - 'echo "disable_vmware_customization: false" >> /etc/cloud/cloud.cfg'
  - echo -n > /etc/machine-id
  - |
    sed -i '' -e 's/match.*/dhcp-identifier: mac/g' -e '/mac/q' /etc/netplan/50-cloud-init.yaml
final_message: "The system is prepped, after $UPTIME seconds"
power_state:
  timeout: 30
  mode: poweroff
  ```

  </details>

If available, use cloud-init to check the user-data file:

```
cloud-init schema --config-file user-data
```


Next, we encode the user-data to base64:
```
base64 -i user-data
```

#### Customising the JSON file

Now we can edit the JSON file we extracted earlier. Change the file with the following:<br>
•	Disk provisioning set to ‘thin’<br>
•	Add the public key of the machine we are connecting from<br>
•	Remove the hostname and password data<br>
•	Set the network for the VM (the name of the relevant portgroup in vCenter)<br>
•	Set the name of the VM<br>
•	In the ‘user-data’ section, paste in the  base64 encoded data<br>

An example of this file can be seen [here](https://raw.githubusercontent.com/vmware-tanzu-experiments/vsphere-with-tanzu-proof-of-concept-samples/main/VCF/test_vms/ubuntu-vm.json)

### Using `jq` to update the VM image JSON
We can either directly hand-edit the VM image JSON or use the `jq` utility (recommended)
<details>
  <summary> 
  Updating the VM JSON using jq: 
  </summary>
  
For example, we can update the `user-data`:

```bash
jq --arg udata "$(base64 -i user-data)" '(.PropertyMapping[] | select(.Key=="user-data")).Value |= $udata' ubuntu-vm.json > ubuntu-vm-updated.json
```

We can add the public key, stored locally:
  
```
jq --arg pubkey "$(cat ~/.ssh/id_rsa.pub)" '(.PropertyMapping[] | select(.Key=="public-keys")).Value |= $pubkey' ubuntu-vm-updated.json > ubuntu-vm-updated-1.json
```
  
Or we could add a public key stored in a user's github profile: <br>
***N.B.: REPLACE WITH DESIRED `USER`!***

```bash
jq --arg pubkey "$(curl -sk https://api.github.com/users/darkmesh-b/keys | jq -r '.[].key')" '(.PropertyMapping[] | select(.Key=="public-keys")).Value |= $pubkey' ubuntu-vm-updated.json > ubuntu-vm-updated-1.json
```
Add the virtual network that the VM will use <br>
***Replace 'DSwitch-DHCP' with the relevant portgroup in your environment***

```bash
jq --arg network "DSwitch-DHCP" '(.NetworkMapping[] | select(.Name=="VM Network")).Network |= $network' ubuntu-vm-updated-1.json > ubuntu-vm-updated-2.json
```
  
Finally, consolidate these changes by overwriting the original json:  

```bash
mv ubuntu-vm-updated-2.json ubuntu-vm.json
```

</details>


Once this JSON file has been defined, we can double-check our user-data encoding is still correct:

```bash
awk -F '"' '/user-data/{getline; print $4}' ubuntu-vm.json | base64 -d''
```


This should return the user-data as we defined above.


## Import OVA to vCenter and Clone
We can then import the OVA into vCenter, specifying our JSON customization file:

```
govc import.ova -options=ubuntu-vm.json -name=ubuntu-template $vmLocation
```


After this has imported, we can update the virtual disk size. Here we set it to 100G:

```
govc vm.disk.change -vm ubuntu-template -disk.label "Hard disk 1" -size 100G
```


Power on the VM to allow it to run cloud-init (and thus our previously defined commands). <br>
**Once complete, the VM will shutdown by itself**

```
govc vm.power -on ubuntu-template
```


Once the VM has shutdown, mark it as a template:

```
govc vm.markastemplate ubuntu-template
```


Finally, we can clone our template VM as we need to. In the example below, we clone it ten times:

```bash
for x in {1..10};do govc vm.clone -vm ubuntu-template ubuntu-vm$x;done
```

To do this for a large number of VMs, in parallel (and output to a log file) we could run:

```
for x in {1..250};do (govc vm.clone -vm ubuntu-template ubuntu-vm$x >> $(date +%d%m-%H%M)_clone.log 2>&1 &);done
```

We can monitor progress by probing the vCenter task-list:

```
govc tasks -f -l
```

## VM Operations

After cloning, we can batch-execute commands on all the VMs. For example, the 'uptime' command (run in parallel:

```bash
govc find -type m -name 'ubuntu-vm*' | xargs -P0 -I '{}' bash -c 'ssh -o "StrictHostKeyChecking=no" ubuntu@$(govc vm.ip {}) uptime -p'
```

A simple bash script can also be written to run commands, for example:

```bash
cat > run_all.sh << EOF
#!/bin/bash
export input=\$1
govc find -type m -name 'ubuntu-vm*' | xargs -P0 -I '{}' bash -c 'ssh -o "StrictHostKeyChecking=no" ubuntu@\$(govc vm.ip {}) "\$input"'
EOF
```

Make the script excutable:

```bash
chmod +x run_all.sh
```

Thus we can then run parallel commands on all the VMs trivially:

```bash
./run_all.sh 'uname -a'
```

## Example, using VMs as worker nodes for FIO

First, set unique hostnames. Easiest way to achive this is to set the hostname to the machine id:

```bash
./run_all.sh 'sudo hostnamectl set-hostname $(cat /etc/machine-id)'
```
Ensure time is being syncronized. We can use NTPD or Chrony (for Ubuntu)

```bash
./run_all.sh 'sudo apt install -y chrony'
```

Install NFS utilities, FIO, etc. This will vary by Linux distro

```bash
./run_all.sh 'sudo apt install -y nfs-common python-3 libaio-dev fio'
```

N.B.: Ensure the same version of FIO is installed locally

Export the IP addresses of the VMs to a file:

```bash
govc find -type m -name 'ubuntu-vm*' | xargs govc vm.ip >> worker_vms
```

Create a mount point

```bash
./run_all.sh 'mkdir -p /mnt/dbfs'
```

Mount the NFS share

```bash
/run_all.sh 'mount -t nfs db-fs3.acme.com:/dbfs3 /mnt/dbfs'
```

Daemonize `FIO` in worker mode:

```bash
./run_all.sh 'fio --server --daemonize=/tmp/fio.pid'
```

We can then run an [FIO test](https://github.com/vmware-tanzu-experiments/vsphere-with-tanzu-proof-of-concept-samples/blob/main/VCF/fio_profiles/file-test.fio) over the workers:

```bash
fio --client=worker_vms file-test.fio
```
