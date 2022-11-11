#!/bin/bash

for x in $(vdq -i | cut -d : -f2 | awk -F\" '{print $2}')
do 
	   esxcli vsan storagepool remove -d $x
done

for x in $(vdq -qH | egrep -o -B2 'Eligible' | grep 'Name:' | awk '{print $NF}')
do 
	partedUtil mklabel /vmfs/devices/disks/$x gpt	
done

esxcli vsan cluster leave
