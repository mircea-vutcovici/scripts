#! /usr/bin/bash

iso_file=$1
# geteltorito -o n2jur14w.img n2jur14w.iso

if [[ $iso_file = "" ]];then
    cat << EOF
    Usage: $0 <iso9660_file>
    Example: $0 n2jur14w.iso
EOF
    exit 1
fi
img_file=${iso_file/iso/img}
set -x
geteltorito -o $img_file $iso_file
