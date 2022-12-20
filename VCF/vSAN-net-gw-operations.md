#  Remove/re-apply gateway for the vSAN vmk adapter for testing
==Only works with with the FIRST vSAN vmk==
TO USE: carefully copy+paste the commands to the esxi shell


## 
## 1. Get the vsan adapter and interface details
## 
```
vmk=$(esxcli vsan network list | awk '/VmkNic/{print $NF;exit}')
for i in 2 3 6;do eval net$i=\" $(esxcli network ip interface ipv4 get -i $vmk | grep $vmk | awk -v I=$i '{print $I}') \";done
```

###
## 2a. remove the gateway
### 
```
esxcli network ip interface ipv4 set -i $vmk -t static -I $net2 -N $net3
```
###
## 2b. re-instate gateway
### 
```
esxcli network ip interface ipv4 set -i $vmk -t static -g $net6 -I $net2 -N $net3
```
