#! /usr/bin/bash
# Parse command line options
if [[ $# == 1 ]];then
    case $1 in
        # We ignore any options and throw an error message
        -*) echo "Usage: $0 <PID>" >&2
            echo "This programs shows the signal masks for a process"
            exit 1 ;;
    esac
    pid=$1
else
    # If PID was missing in the command line, we ask for it
    read -p "PID=" pid
fi

# Name of the item that had a signal mask in hex
item_name=""

# bitmask represented as a hex number
item_hex_mask=""

# For all lines that contains a signal bitmask for the process with PID $pid read the "queue" name and the bitmask
cat /proc/$pid/status|grep -E '(Sig|Shd)(Pnd|Blk|Ign|Cgt)'|while read item_name item_hex_mask;do
    # Transform the bit mask from hex to binary:
    item_bin_mask=$(echo "ibase=16; obase=2; ${item_hex_mask^^*}"|bc)
    echo -n "$item_name $item_hex_mask $item_bin_mask "
    # We use i to iterate for each signal starting from 1 to when there are not anymore bits to check
    i=1
    # For each bit from the mask, starting with the least significant one
    while [[ $item_bin_mask -ne 0 ]];do
        # If the bit is set
        if [[ ${item_bin_mask:(-1)} -eq 1 ]];then
            # We print the signal's name
            kill -l $i | tr '\n' ' '
        fi
        # We remove the least significant bit from the mask:
        item_bin_mask=${item_bin_mask::-1}
        # We continue with next signal number
        set $((i++))
    done
    echo
done
# vim:et:sw=4:ts=4:sts=4:
