# Creating Test VMs
Here we demonstrate how to quickly create a set of identical VMs for testing.<br>
For a more verbose procedure, visit Myles Gray’s blog: 
https://blah.cloud/infrastructure/using-cloud-init-for-vm-templating-on-vsphere

## Requirements:
•	FreeBSD, Linux or MacOS VM/host environment<br>
•	Latest version of govc (download instructions below)

## Download govc:
Govc is a lightweight, open-source CLI tool written in Go (and part of the Govmomi/Go library for the vSphere API). Project page: https://github.com/vmware/govmomi/tree/master/govc<br>

To download the latest release, use the command below. As with the majority of Go projects, it is packaged as a single binary (note that the tar command requires root privileges to copy the binary to the correct location):

``` 
curl -L -o - "https://github.com/vmware/govmomi/releases/latest/download/govc_$(uname -s)_$(uname -m).tar.gz" | tar -C /usr/local/bin -xvzf - govc
```

## Connecting to vCenter
To authenticate with vCenter, we need to define the username, password and URL, as per the example below:
``` 
export GOVC_USERNAME=administrator@vsphere.local 
export GOVC_PASSWORD=P@ssw0rd
export GOVC_INSECURE=1
export GOVC_URL=10.156.163.1 
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

Ubuntu uses cloud-init to setup the OS. As we will be cloning the deployed VM, we need to define specific user-data (which will be encoded in base-64 and added to the customization JSON). Here we ensure that vSphere specific configuration is not disabled, and we modify the default netplan config file to ensure DHCP addresses are assigned by mac address.
To simplify the process, the user-data file can be downloaded from the link below:
https://raw.githubusercontent.com/vmware-tanzu-experiments/vsphere-with-tanzu-proof-of-concept-samples/main/VCF/test_vms/user-data

<details>
  <summary> 
  Example user-data file: 
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

Now we can edit the JSON file we extracted earlier. Change the file with the following:<br>
•	Disk provisioning set to ‘thin’<br>
•	Add the public key of the machine we are connecting from<br>
•	Remove the hostname and password data<br>
•	Set the network for the VM (the name of the relevant portgroup in vCenter)<br>
•	Set the name of the VM<br>
•	In the ‘user-data’ section, paste in the  base64 encoded data<br>

An example of this file can be seen here:
https://raw.githubusercontent.com/vmware-tanzu-experiments/vsphere-with-tanzu-proof-of-concept-samples/main/VCF/test_vms/ubuntu-vm.json

Note we can avoid hand-editing the json by using `jq`
<details>
  <summary> 
  Updating the VM JSON using jq: 
  </summary>
  
For example, we can update the `user-data`:

```bash
jq --arg udata "$(base64 -i user-data)" '(.PropertyMapping[] | select(.Key=="user-data")).Value |= $udata' ubuntu-vm.json > ubuntu-vm-updated.json
```

Similarly, adding a public key stored in a user's github profile:
  N.B.: REPLACE WITH DESIRED USER!

```bash
jq --arg pubkey "$(curl -sk https://api.github.com/users/darkmesh-b/keys | jq -r '.[].key')" '(.PropertyMapping[] | select(.Key=="public-keys")).Value |= $pubkey' ubuntu-vm-updated.json > ubuntu-vm-updated-again.json
```

Finally, consolidate these changes by overwriting the original json:  

```bash
mv ubuntu-vm-updated-again.json ubuntu-vm.json
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


Power on the VM to allow it to run cloud-init (and thus our previously defined commands). Once complete, the VM will shutdown:

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

After cloning, we can batch-execute commands on all the VMs. For example, the 'ls' command:

```bash
govc find -type m -name 'ubuntu-vm*' | xargs -P0 -I '{}' bash -c 'ssh -o "StrictHostKeyChecking=no" ubuntu@$(govc vm.ip {}) ls'
```

