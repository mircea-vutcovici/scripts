#! /bin/bash

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
    local log_message="$@"   # All remaining parameters
    local log_color=""
    local log_color_reset=""
    if [[ $DEBUG == "1" || $log_message_level != "DEBUG" ]];then
        if [ -t 1 -a -t 2 ] ; then  # STDOUT is a terminal
            case $log_message_level in
                DEBUG)  log_color=$(tput setaf 4; tput bold) ;; # light blue
                INFO)   log_color=$(tput setaf 2; tput bold) ;;  # light green
                WARNING)log_color=$(tput setaf 3; tput bold) ;; # yellow
                ERROR)  log_color=$(tput setaf 1; tput bold) ;; # light red
                FATAL)  log_color=$(tput setaf 1) ;; # red
                *)      log_color=$(tput setaf 1; tput blink);; # blinking red
            esac
            log_color_reset=$(tput sgr0) # turn off all attributes
        fi
        printf '%(%F %T)T %b\n' -1 "$log_color$log_message_level$log_color_reset: $log_message" >&2
    fi
    case $log_message_level in
        ERROR|FATAL) ERRORS_FOUND=1 # We will send an email with the log in the exit_trap function.
        dump_stack
    esac
}
print_bold(){
    local command_to_print="$1"
    local command_description="$2"
    local command_color=""
    local description_color=""
    local command_color_reset=""
        if [ -t 1 -a -t 2 ] ; then  # STDOUT is a terminal
            command_color=$(tput bold) # bold
            description_color=$(tput setaf 2; tput bold) # light green
            command_color_reset=$(tput sgr0) # turn off all attributes
        fi
    if [[ "$command_description" == "" ]];then
        printf '%b\n' "$command_color$command_to_print$command_color_reset"
    else
        printf '%b\n' "$command_color$command_to_print$command_color_reset \t# $description_color$command_description$command_color_reset"
    fi
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
        log WARNING "Dry run. The execution of \"$shell_expression\" has been skipped."
        return 0
    else
        log DEBUG "Starting \"$shell_expression\""
        local pipefail_save=$(set +o |grep pipefail)  # save the current status of pipefail bash option.
        local error_code=123
        local random_key=$RANDOM$RANDOM
        local regex="errorcode-$random_key=([0-9]+)"
        # TODO: Disable buffering with: stdbuf -oL
        { eval "set -o pipefail && $shell_expression" ;echo errorcode-$random_key=$? ; }|&  while IFS= read -r line; do
            if [[ $line =~ $regex ]];then
                return ${BASH_REMATCH[1]}
            fi
            log DEBUG "    | $line"
        done
        error_code=$?
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
    local real_block_device=$block_device
    local error_code=254
    if [ -L $block_device ];then
        real_block_device=$(readlink -f $block_device)
    fi
    # Check if the block device is a DM (device mapper) volume, then expand first underlying devices.
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
                log DEBUG "going deeper."
                expand_block_device $(find /dev -type b|xargs ls -l|sed -rn "/ $major, +$minor /s/.* \/dev/\/dev/p")
            fi
        done
    fi

    # Check if the device is a MD device (Software RAID), then resize it. Go down in recursion if needed.
    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is a MD device and resize it."
    if grep -q raid /sys/block/$(basename $real_block_device)/md/level >/dev/null 2>&1;then
        log DEBUG "\"$block_device\" is a MD device"
        for maj_min in $(< /sys/block/$(basename $real_block_device)/md/rd*/block/dev);do
            log DEBUG maj_min=$maj_min
            major=${maj_min/:*/}
            minor=${maj_min/*:/}
            if devmap_name $maj_min >/dev/null;then
                log DEBUG "going deeper."
                expand_block_device /dev/mapper/$(devmap_name $maj_min)
            else
                log DEBUG "going deeper."
                expand_block_device $(find /dev -type b|xargs ls -l|sed -rn "/ $major, +$minor /s/.* \/dev/\/dev/p")
            fi
        done
        return $?
    fi

    # Check if the block device is a MS-DOS or GPT partition, then expand first underlying devices.
    log DEBUG "Check if \"$block_device\" is a MS-DOS or UEFI GPT partition."
    if [[ $(< /sys/class/block/$(basename $block_device)/partition) -ge 1 ]] 2>/dev/null;then
        log DEBUG "The block device \"$block_device\" is a MS-DOS or UEFI GPT partition."
        log DEBUG "Check if \"$block_device\" is an UEFI GPT partition."
        local disk_device=/dev/$(basename $(dirname $(readlink -f /sys/class/block/$(basename $block_device))))
        if dd if=$disk_device bs=512 count=1 skip=1 2>/dev/null|grep -q "^EFI PART";then
            log DEBUG "The block device \"$block_device\" is an UEFI GPT partition."
            expand_gpt_partition $block_device && update_disklabel $block_device
            return $?
        fi
        log DEBUG "Check if \"$block_device\" is an MS-DOS partition."
        if fdisk -l $disk_device|grep -q "^Disk.*label type: dos$";then
            # Is bootable: dd if=/dev/sda bs=1 count=2 skip=510 2>/dev/null|hexdump -e '/1 "%02X "'
            #    returns: 55 AA
            log DEBUG "The block device \"$block_device\" is a MS-DOS partition."
            expand_msdos_partition $block_device && update_disklabel $block_device
            return $?
        fi
        die "The disk label of the \"$block_device\" device could not be if it is MS-DOS or UEFI GPT."
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is a SCSI device and rescan it."
    if [ "$(readlink -f /sys/block/$(basename $real_block_device)/device/driver)" = "/sys/bus/scsi/drivers/sd" -o \
          "$(readlink -f /sys/block/$(basename $real_block_device)/device/generic/driver)" = "/sys/bus/scsi/drivers/sd" ];then
        log DEBUG "\"$block_device\" is a SCSI device."
        # Check if the SCSI target can be resized.
        # Check that scsi_level is equal or above 6
        # The support for resize was defined in SCSI SPC-3. Also multipath and ALUA is described in T10 SCSI-3 specification SPC-3, section 5.8. http://www.csit-sun.pub.ro/~cpop/Documentatie_SMP/Standarde_magistrale/SCSI/spc3r17.pdf
        # From Linux kernel:
        #   include/scsi/scsi.h:#define SCSI_SPC_3      6
        local SCSI_SPC_3=6
        if [[ $(< /sys/block/$(basename $block_device)/device/scsi_level) -ge $SCSI_SPC_3 ]];then
            log DEBUG "\"$block_device\" can be resized online."
        else
            log WARNING "\"$block_device\" can not be resized online, the hardware SCSI level is lower than 6 (SCSI_SPC_3), and the machine must be rebooted. $(< /sys/block/$(basename $block_device)/device/scsi_level) < $SCSI_SPC_3"
        fi
        rescan_block_device $block_device && update_disklabel $block_device
        return $?
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is a NVME device and rescan it."
    if ls -ld /sys/block/$(basename $real_block_device)/device/subsystem |& grep -q nvme ;then
        log DEBUG "\"$block_device\" is a NVME device."
        rescan_nvme_block_device $block_device && update_disklabel $block_device || die Could not generate rescan or update disklabel commands.
        return $?
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is a Virtio block device."
    if [ "$(readlink -f /sys/block/$(basename $real_block_device)/device/driver)" = "/sys/bus/virtio/drivers/virtio_blk" -o \
          "$(readlink -f /sys/block/$(basename $real_block_device)/device/generic/driver)" = "/sys/bus/virtio/drivers/virtio_blk" ];then
        # TODO: add commands for qemu/libvirtd to resize the block device
        #    Find the block device name in qemu:
        #        virsh domblklist <libvirtd_vm_name>
        #        virsh qemu-monitor-command <libvirtd_vm_name> info block --hmp
        #    Pay attention for the disk name, should be similar to "drive-virtio-disk0".
        #    Resize the disk:
        #        virsh blockresize --domain <libvirtd_vm_name> --path drive-virtio-disk0 --size 20G
        #        virsh qemu-monitor-command <libvirtd_vm_name> block_resize drive-virtio-disk0 20G --hmp
        log DEBUG "\"$block_device\" is a Virtio block device."
        update_disklabel $block_device
        return $?
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is DM multipath."
    if dmsetup table|grep -q $(basename $block_device).*multipath; then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a DM multipath volume."
        expand_mp_device $block_device && update_disklabel $block_device
        return $?
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is DM crypt."
    if cryptsetup status $real_block_device |& grep -Eq "type:[[:space:]]+LUKS"; then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a DM crypt volume."
        expand_crypt_device $block_device && update_disklabel $block_device
        return $?
    fi

    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is LVM2 logical volume."
    if lvs -o lv_name --noheadings $block_device >/dev/null 2>&1;then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a LVM logical volume."
        expand_lvm2_lv $block_device
        return $?
    fi
    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" device is a loop volume."
    if [ -f /sys/block/$(basename $real_block_device)/loop/backing_file ];then
        local loop_backing_file=$(</sys/block/$(basename $real_block_device)/loop/backing_file)
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a loop volume mapped from \"$loop_backing_file\"."
        expand_loop_device $block_device
        return $?
    fi
    log DEBUG "Check if \"$block_device\" aka \"$real_block_device\" is a file."
    if [ -f $block_device ];then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a file."
        expand_raw_file $loop_backing_file
        return $?
    fi
    die "The type of the \"$block_device\" device could not be determined."
}
rescan_block_device(){
    local block_device=$1   # Full path to the device name
    local block_device_short=$(basename $block_device)
    # SCSI Read Capacity(16) or Read Capacity(10)
    local block_device_rescan_file=$(readlink -f /sys/block/$block_device_short/device/rescan)
    log DEBUG "Rescan file: $block_device --> $block_device_rescan_file"
    if [ "x$block_device_rescan_file" == "x" ];then
        log ERROR "Block device \"$block_device\" can not be scanned. It must be resized manually."
        return 1
    fi
    # Print the following warning only once
    if [ -z ${rescan_block_device_warning+x} ];then
         rescan_block_device_warning="displayed"
        log WARNING "Make sure you run next \"echo\" commands all at once, if there are more than 1. If the \"echo\" commands are not run in a short timpespan, the DM multipath devices will go into suspended state. If the multipath volume is frozen, resume disk I/O with: dmsetup resume /dev/mapper/mpath...."
    fi
    print_bold "echo 1 > $block_device_rescan_file" "Send SCSI Read Capacity(16) or Read Capacity(10) command to obtain the new size"
    return 0
}

rescan_nvme_block_device(){
    # TODO: Do we need also "reset_controller", not only "rescan_controller"?
    local block_device=$1   # Full path to the device name
    local block_device_short=$(basename $block_device)   # This is the NVME namespace, like: nvme0n1
    local block_device_rescan_file=$(readlink -f /sys/block/$block_device_short/device/rescan_controller)
    print_bold "echo 1 > $block_device_rescan_file" "Rescan NVME controller. This will also find and create device files for new NVME namespaces."
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
        # We return here even if there is no change to skip LVM expand.
        return 1
    fi

    log DEBUG "Detect if the device \"$block_device\" is a LVM2 physical volume and resize it."
    if pvs --noheadings  -o pv_name $real_block_device >/dev/null 2>&1 || pvs --noheadings  -o pv_name $block_device >/dev/null 2>&1; then
        log DEBUG "The \"$real_block_device\" device aka \"$block_device\" is a LVM physical volume."
        expand_lvm2_pv $block_device
        return $?
    fi
    # FIXME: This message is misleading
    #log DEBUG "Could not determine the disk label for \"$block_device\"."
    return 0
}

expand_gpt_partition(){
    local gpt_part_device=$1
    if [[ $(< /sys/class/block/$(basename $gpt_part_device)/partition) -ge 1 ]] 2>/dev/null;then
    log DEBUG "The block device $gpt_part_device is partition $(< /sys/class/block/$(basename $gpt_part_device)/partition )."
    else
        die "The block device $gpt_part_device is not a UEFI GPT partition"
    fi
    # Find the main block device where this partion is member
    local gpt_disk_device=/dev/$(basename $(dirname $(readlink -f /sys/class/block/$(basename $gpt_part_device))))
    local gpt_part_table_backup_name=dev_$(basename $gpt_disk_device)-'partition-table-$(date +%F_%H%M%S).txt'
    print_vold "sgdisk --backup=$gpt_part_table_backup_name $gpt_disk_device" "Backup UEFI GPT partition table"
    log DEBUG "going deeper."
    expand_block_device $gpt_disk_device
    local gpt_part_number=$(< /sys/class/block/$(basename $gpt_part_device)/partition)
    # TODO: if parted doesn't support resize, then try with:
    # echo ", +" | sgdisk -N 2 /dev/vda --no-reread
    print_bold "parted -s $gpt_disk_device resizepart $gpt_part_number" "Resize GPT partition $gpt_part_device"
    log INFO "Update kernel with new partition table from disk"
    print_bold "partx -u $gpt_disk_device"
    print_bold "partprobe $gpt_disk_device"
    print_bold "blockdev --rereadpt $gpt_disk_device"
    print_bold "kpartx -u $gpt_disk_device"
    return $?
}
expand_msdos_partition(){
    local msdos_part_device=$1
    if [[ $(< /sys/class/block/$(basename $msdos_part_device)/partition) -ge 1 ]] 2>/dev/null;then
    log DEBUG "The block device $msdos_part_device is partition $(< /sys/class/block/$(basename $msdos_part_device)/partition )."
    else
        die "The block device $msdos_part_device is not a MS-DOS partition"
    fi
    # Find the main block device where this partion is member
    local msdos_disk_device=/dev/$(basename $(dirname $(readlink -f /sys/class/block/$(basename $msdos_part_device))))
    log DEBUG "Backup partition table for device $msdos_part_device"
    local msdos_part_table_backup_name=dev_$(basename $msdos_disk_device)-'partition-table-$(date +%F_%H%M%S).txt'
    print_bold "sfdisk -d $msdos_disk_device > $msdos_part_table_backup_name" "Backup MS-DOS partition table for $msdos_disk_device block device."
    log DEBUG "going deeper."
    expand_block_device $msdos_disk_device
    local msdos_part_number=$(< /sys/class/block/$(basename $msdos_part_device)/partition)
    # TODO: if parted doesn't support resize, then try with:
    # echo ", +" | sfdisk -N 2 /dev/vda --no-reread
    print_bold "parted -s $msdos_disk_device resizepart $msdos_part_number" "Resize MS-DOS partition $msdos_part_device"
    log INFO "Update kernel with new partition table from disk"
    print_bold "partx -u $msdos_disk_device"
    print_bold "partprobe $msdos_disk_device"
    print_bold "blockdev --rereadpt $msdos_disk_device"
    print_bold "kpartx -u $msdos_disk_device"
    return $?
}
expand_lvm2_lv(){
    local lv_device=$1
    print_bold "lvextend -l +90%FREE $lv_device" "Extend the logical volume to 90% of free space in volume group."
    return $?
}
expand_lvm2_pv(){
    local pv_device=$1
    log DEBUG "Expanding physical volume \"$pv_device\"."
    print_bold "pvresize $pv_device" "Expand LVM physical volume $pv_device"
    return $?
}
expand_mp_device(){
    local mp_device=$1
    log DEBUG "Expanding multipath volume \"$mp_device\"."
    print_bold "multipathd -k\"resize map $(basename $mp_device)\"" "Expand DM Multipath (MPIO) device"
    return $?
}
expand_crypt_device(){
    local crypt_device=$1
    log DEBUG crypt_device=$crypt_device
    run cryptsetup status $crypt_device
    local crypt_device_parent=$(cryptsetup status $crypt_device|sed -rn 's/^[[:space:]]+device:[[:space:]]+//p')
    log DEBUG "Check if $crypt_device_parent, parent of $crypt_device device, is a LUKS device."
    if cryptsetup isLuks $crypt_device_parent;then
        log DEBUG "The \"$crypt_device_parent\" device contains a LUKS encrypted volume."
        print_bold "cryptsetup resize  $crypt_device_parent"  "Resize LUKS encrypted volume $crypt_device"
    else
        log ERROR "Can not resize crypt device $crypt_device. It is not a LUKS volume."
    fi
    return $?
}
expand_loop_device(){
    local loop_device=$1
    local loop_backing_file=$(</sys/block/$(basename $real_block_device)/loop/backing_file)
    expand_block_device $loop_backing_file
    log DEBUG "Expand loop device \"$loop_device\""
    echo "losetup --set-capacity $loop_device   # Resize loop block device"
    return $?
}
expand_raw_file(){
    local loop_backing_file=$1
    log DEBUG "Expand raw file \"$loop_backing_file\""
    print_bold "dd conv=notrunc oflag=append bs=1M count=1 if=/dev/zero of=$loop_backing_file" "Append 1MB NULL characters to the file"
    #print_bold "fallocate --posix --length 2G $loop_backing_file" "Append 1MB NULL characters to the file"
    #print_bold "truncate -s +1M $loop_backing_file" "Append 1MB NULL characters to the file"
}
resize_fs(){  # Determine the filesystem and resize it
    local fs_device=$1
    local fs_type=$(blkid $fs_device|sed -r 's/.*TYPE="([^"]*)".*/\1/')
    local mountpoints="$(grep $fs_device /proc/mounts |awk '{print $2}')"
    log DEBUG "Resizing the file system on \"$fs_device\""
    if [ x"$fs_type" == "x" ];then
        log DEBUG "Getting the filesystem type from /proc/mounts"
        # GFS can be expanded only if it is mounted
        if grep -Eq "^$fs_device [^ ]+ gfs " /proc/mounts ;then
            fs_type=gfs
        fi
    fi
    case $fs_type in
        xfs)
                print_bold "xfs_growfs $fs_device" "Resize XFS file system"
                ;;
        ext*)
                print_bold "resize2fs $fs_device" "Resize ext3 or ext4 filesystem"
                ;;
        gfs)
                if ! clustat -Q ;then
                    die "Cluster is not quorate."
                fi
                log WARNING "Make sure you run the rescan on all RHEL cluster members"
                print_bold gfs_grow -T $fs_device
                print_bold gfs_grow $fs_device
                ;;
        swap)
                log WARNING "Make sure you have enough free memory to load the data from this swap device when you run swapoff command."
                print_bold "swapoff $fs_device" "Disable swap device."
                print_bold "mkswap $fs_device" "Set the swap area."
                print_bold "swapon $fs_device" "Enable swap device."
                ;;
        btrfs)
                if [ $(echo "$mountpoints"|wc -l) -gt 1 ];then
                    log WARNING "Multiple btrfs file systems detected. You should chose only one. Block: $fs_device, Filesystems: ${mountpoints/$'\n'/, }"
                fi
                echo "$mountpoints"|while read mountpoint;do
                    print_bold "btrfs filesystem resize max \"$mountpoint\"" "Resize BTRFS file system mounted on $mountpoint"
                done
                ;;

        *)
                log ERROR "File system \"$fs_type\" from device \"$fs_device\" is not supported."
                ;;
    esac
}

# }}}

# {{{ Validate input
if [  $# -lt 1 ];then
    die "Invalid number of arguments. \$#=$#"
fi

if [[ $(id -ru) != 0 ]];then
    log WARNING "This script needs to run as root user."
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
                        if ! grep -q "^$block_device_to_expand" /proc/mounts;then
                            log ERROR "\"$block_device_to_expand\" is not mounted."
                        fi
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
# lsblk -o NAME,VENDOR,MODEL,SERIAL,LABEL,UUID,ID,MAJ:MIN,PHY-SEC,LOG-SEC,RA,SIZE,RO,FSTYPE,MOUNTPOINT
# http://rescan-scsi-bus.sh/ latest ftp://31.3.72.196/gentoo/distfiles/rescan-scsi-bus.sh-1.57

if [ $DEBUG == 1 ];then
    #ssm list
    #dmsetup ls --tree; multipath -ll; lvs; vgs; pvs; echo
    print_dm_tree $block_device_to_expand_short
    #dmsetup deps testvg-testlv
    #devmap_name 252 0
    #udevadm info -an /dev/sda
    #udevadm info --export-db
    #file -s /dev/sdaa # Returns UUID
    #systool -c fc_host -v
    #sg_inq --id /dev/sdaa|sed -rn 's/.*[[]0x([0-9a-f]{32})[]].*/\1/p'  # Returns WWID used to group devices in a DM Multipath
    # https://blogs.it.ox.ac.uk/oxcloud/2013/03/25/rescanning-your-scsi-bus-to-see-new-storage/
    # scsi_logging_level –hlqueue 3 –highlevel 2 –all 1 -s
    # echo 12345123123123 > /proc/sys/dev/scsi/logging_level
fi

expand_block_device $block_device_to_expand #|| die Could not expand \"$block_device_to_expand\" block device.
resize_fs $block_device_to_expand
# vim:ts=4:sts=4:et:sw=4
