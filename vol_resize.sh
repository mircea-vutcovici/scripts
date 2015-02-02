#! /bin/bash

# Author: Mircea Vutcovici 2014

# {{{ Initialization
DEBUG=0
DRY_RUN=0
# }}}

# {{{ Functions
usage(){
    cat << EOF

This script resize a block device that is mounted. It will rescan the SCSI bus, it will resize the multipath block device, the volume (LVM or partition table), then the filesystem.
Some configuration items can be edited at the top of this script.
Usage: $0 [--debug] --block-device <block_device>
Examples:
    $0 --block-device /dev/mapper/mp_vol1
    $0 --debug --block-device /dev/mapper/mp_vol1
    $0 --debug --dry-run --block-device /dev/mapper/mp_vol1
The option --debug can be added for debugging purposes.
The option --dry-run will simultate the change.
EOF
}
log(){
    local log_message_level=$1 # DEBUG, INFO, WARNING, ERROR, FATAL
    shift
    local log_message="$@"
    if [[ $DEBUG == "1" || $log_message_level != "DEBUG" ]];then
        echo $(date +%F\ %T) $log_message_level: "$log_message" >&2
    fi
    case $log_message_level in
        ERROR|FATAL) ERRORS_FOUND=1 # We will send an email with the log in the exit_trap function.
        dump_stack
    esac
}
die(){
    local error_message="$@"
    log FATAL "$error_message Stack trace:"
    usage
    exit 1
}
run(){
    local shell_expression="$@"
    if [[ $DRY_RUN == "1" ]];then
        log WARNING "Dry run. The execution of \""$shell_expression"\" has been skipped."
        return 0
    else
        log DEBUG "Starting \""$shell_expression"\""
        local pipefail_save=$(set +o |grep pipefail)  # save the current status of pipefail bash option.
        eval "set -o pipefail && $shell_expression"
        local error_code=$?
        eval $pipefail_save  # restore the status of pipefail bash option, we need to restore it after the $shell_expression has run otherwise the exit code will be always 0.
        log DEBUG "The command \""$shell_expression"\" ended with error code $error_code"
        return $error_code
    fi
}
dump_stack(){
    local i=0
    local line_no
    local function_name
    local file_name
    #while caller $i ;do ((i++)) ;done | sed 's/ /\t/g;s/^/\t/' >&2
    while caller $i ;do ((i++)) ;done | while read line_no function_name file_name;do echo -e "\t$file_name:$line_no\t$function_name" ;done >&2
}

#-----------------------------

devmap_name(){ # This accepts only one parameter in the format "major:minor" or "major minor". Returns the DM block device matching the major and minor.
    local maj_min=$1
    local major=0
    local minor=0
    case $# in
        1)
            major=${maj_min/:*/}
            minor=${maj_min/*:/}
            ;;
        2)
            major=$1
            minor=$2
            ;;
        *) die "Invalid number of arguments for devmap_name()." \$#=$#.
            ;;
    esac
    dmsetup info -c --noheadings -o name -j $major -m $minor 2>/dev/null
    local error_code=$?
    return $error_code
}
majmin_device(){
    local block_device=$1
    echo $(ls -ld --dereference $block_device|sed -r "s/.*([0-9]+), +([0-9]+).*/\1:\2/")
    return $?
}
print_dm_tree(){ # Print the device mapper tree for a DM device. Example: print_dm_tree testvg-testlv
    local dm_block_device=$1
    dmsetup ls --tree -o ascii|sed -n '/'$dm_block_device'/,/^[^ ]/p'|sed -rn '/'$dm_block_device'|^ /p'
}
expand_block_device(){ # Recursively call itself and resize each device (block, multipath or LVM)
    local block_device=$1   # Full path to the device name
    local maj_min="0:0"
    local minor=0
    local major=0
    local block_device_to_scan=""
    local real_block_device=$block_device
    local error_code=254
    if [ -L $block_device ];then
        real_block_device=$(readlink -f $block_device)
    fi
    log DEBUG "Expanding $block_device --> $real_block_device. Command: \"dmsetup deps $real_block_device\" returns \"$(dmsetup deps $real_block_device 2>&1)\""
    if dmsetup deps $real_block_device >/dev/null 2>&1;then # The file is a DM device, we go deep into recursion.
        for maj_min in $(dmsetup deps $real_block_device|sed -r 's/^[^(]+\(//;s/(\) \()/ /g;s/\)$//;s/, /:/g');do
            log DEBUG "maj_min=$maj_min"
            major=${maj_min/:*/}
            minor=${maj_min/*:/}
            if devmap_name $maj_min >/dev/null;then
                log DEBUG "going deeper."
                expand_block_device /dev/mapper/$(devmap_name $maj_min)
            else
                expand_block_device $(find /dev -type b|xargs ls -l|sed -rn "/ $major, +$minor/s/.* \/dev/\/dev/p")
            fi
        done
    fi

    # Check if the device is a MD device (Software RAID), then resize it. Go down in recursion if needed.
    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is a MD device and resize it."
    if grep -q raid /sys/block/$(basename $real_block_device)/md/level >/dev/null 2>&1;then
        log DEBUG "\"$block_device\" is a MD device"
        for maj_min in $(cat /sys/block/$(basename $real_block_device)/md/rd*/block/dev);do
            log DEBUG maj_min=$maj_min
            major=${maj_min/:*/}
            minor=${maj_min/*:/}
            if devmap_name $maj_min >/dev/null;then
                log DEBUG going deeper.
                expand_block_device /dev/mapper/$(devmap_name $maj_min)
            else
                expand_block_device $(find /dev -type b|xargs ls -l|sed -rn "/ $major, +$minor/s/.* \/dev/\/dev/p")
            fi
        done
        return $?
    fi


    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is a SCSI device and rescan it."
    if [ "$(readlink -f /sys/block/$(basename $real_block_device)/device/driver)" = "/sys/bus/scsi/drivers/sd" ];then
        log DEBUG "\"$block_device\" is a SCSI device."
        rescan_block_device $block_device && update_disklabel $block_device
        return $?
    fi

    # TODO: detect UEFI partitions

    log DEBUG "Check if \"$block_device\" is a MS-DOS partition."
    if [[ $(cat /sys/class/block/$(basename $block_device)/partition 2>/dev/null) -ge 1 ]];then
        log ERROR "The block device \"$block_device\" is an MS-DOS partition. Which is not supported yet. You have to expand it manually."
        # resize_partition $block_device && update_disklabel $block_device
        return 1
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is DM multipath."
    if dmsetup table|grep -q $(basename $block_device).*multipath; then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a DM multipath volume."
        expand_mp_device $block_device && update_disklabel $block_device
        return $?
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is LVM2 logical volume."
    if lvs -o lv_name --noheadings $block_device >/dev/null 2>&1;then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a LVM logical volume."
        expand_lvm2_lv $block_device
        return $?
    fi
    die "The type of the \"$block_device\" device could not be determined."
}
rescan_block_device(){
    local block_device=$1   # Full path to the device name
    local block_device_short=$(basename $block_device)
    local block_device_rescan_file=$(readlink -f /sys/block/$block_device_short/device/rescan)
    log DEBUG "Rescan file: $block_device --> $block_device_rescan_file"
    if [ "x$block_device_rescan_file" == "x" ];then
        log ERROR "Block device \"$block_device\" can not be scanned. It must be resized manually."
        return 1
    fi
    echo "echo 1 > $block_device_rescan_file"
    return 0
}

update_disklabel(){
    # Some block devices have a disk label.
    # Devices: SCSI disk, MP LUN, MD RAID, loop
    # Disk label types: MS-DOS partition table, LVM2
    # Where should be zfs and btrfs subvolumes?
    local block_device=$1
    local real_block_device=$block_device
    if [ -L $block_device ];then
        real_block_device=$(readlink -f $block_device)
    fi
    log DEBUG "Check if \"$block_device\" device is part of a DM multipath and exit."
    # You can test this also with: multipath -c /dev/sdi
    if dmsetup table| grep -q " multipath .*$(majmin_device $block_device)";then
        log DEBUG "Device \"$block_device\" is member of a DM multipath. The disk label will be expanded via the DM multipath block device, not from members."
        return 1
    fi

    log DEBUG "Detect if the device \"$block_device\" is a LVM2 physical volume and resize it."
    if pvs --noheadings  -o pv_name $real_block_device >/dev/null 2>&1 || pvs --noheadings  -o pv_name $block_device >/dev/null 2>&1; then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a LVM physical volume."
        expand_lvm2_pv $block_device
        return $?
    fi
    log DEBUG "Could not determine the disk label for \"$block_device\"."
    return 0
}
expand_lvm2_lv(){
    local lv_device=$1
    echo lvextend -l +90%FREE $lv_device
    return $?
}
expand_lvm2_pv(){
    local pv_device=$1
    log DEBUG "Expanding physical volume \"$pv_device\"."
    echo pvresize $pv_device
    return $?
}
expand_mp_device(){
    local mp_device=$1
    log DEBUG "Expanding multipath volume \"$mp_device\"."
    echo multipathd -k\"resize map $(basename $mp_device)\"
    return $?
}
resize_fs(){  # Determine the filesystem and resize it
    local fs_device=$1
    local fs_type=$(blkid $fs_device|sed -r 's/.*TYPE="(.*)".*/\1/')
    local error_code=254
    log DEBUG "Resizing the file system on \"$fs_device\""
    case $fs_type in
        xfs)
                echo xfs_growfs $fs_device
                error_code=$?
                ;;
        ext*)
                echo resize2fs $fs_device
                error_code=$?
                ;;
        *)
            log ERROR "File system \"$fs_type\" from device \"$fs_device\" is not supported."
                ;;
    esac
    return $error_code
}

# }}}

# {{{ Validate input
if [  $# -lt 1 ];then
    die Invalid number of arguments. "\$#=$#"
fi

while [[ $# > 0 ]]; do
    argument=$1
    shift
    case $argument in
        -h|--help)      usage; exit ;;
        -n|--dry-run)   DRY_RUN=1 ;;
        --debug)
                        DEBUG=1 ;
                        # Die if variables are not set
                        set -o nounset
                        log DEBUG "Debug enabled from command line."
                        ;;
        --block-device)
                        if [ ! -n "${1-}" ];then
                            die The option --block-device requres an argument.
                        fi
                        block_device_to_expand=$1
                        block_device_to_expand_short=$(basename $block_device_to_expand)
                        ls -ld --dereference $block_device_to_expand |grep -q ^b || die \"$block_device_to_expand\" is not a block device.
                        df $block_device_to_expand >/dev/null || log ERROR "\"$block_device_to_expand\" is not mounted."
                        shift
                        ;;
        *) die Unknown command line option \"$argument\";;
    esac
done
# }}}

# blkdeactivate - only supported by redhat.
# blkid - see if required.
# dmsetup ls --tree -o ascii
# lsblk - to determine if it is a disk partition or logical volume
# http://rescan-scsi-bus.sh/ latest ftp://31.3.72.196/gentoo/distfiles/rescan-scsi-bus.sh-1.57

if [ $DEBUG == 1 ];then
    #dmsetup ls --tree; multipath -ll; lvs; vgs; pvs; echo
    print_dm_tree $block_device_to_expand_short
    #dmsetup deps testvg-testlv
    #devmap_name 252 0
    #udevadm info -an /dev/sda
    #udevadm info --export-db
    #file -s /dev/sdaa
fi

expand_block_device $block_device_to_expand #|| die Could not expand \"$block_device_to_expand\" block device.
resize_fs $block_device_to_expand
