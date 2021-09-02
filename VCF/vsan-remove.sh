#!/bin/bash

for x in $(vdq -iH | grep "SSD:" | awk '{print $NF}')
do 
	   esxcli vsan storage remove -s $x
done

for x in $(vdq -qH | egrep -o -B2 'Eligible' | grep 'Name:' | awk '{print $NF}')
do 
	partedUtil mklabel /vmfs/devices/disks/$x gpt	
done

esxcli vsan cluster leave
