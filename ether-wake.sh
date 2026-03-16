#! /usr/bin/bash

# First argument is the MAC address of the remote machine to wake up
mac=$(echo ${1,,} | sed 's/[ :-]//g' | fold -w2)

broadcast_ip=$(ipcalc -b $(ip r |grep link.*$(ip r g 8.8.8.8|awk '{print $7}')|awk '{print $1}')|sed 's/BROADCAST=//')
port=9


magic_packet="\xff\xff\xff\xff\xff\xff$(echo ${1,,}| sed 's/[ :-]//g'|sed -E 's/(..)/\\x\1/g; s/(.*)/\1\1\1\1\1\1\1\1\1\1\1\1\1\1\1\1/')"

echo -en $magic_packet | nc -u $broadcast_ip $port
#ping -c1 -b $broadcast_ip -p "$(echo $magic_packet|sed 's/\\x//g')"
