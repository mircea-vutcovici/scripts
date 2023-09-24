# Update package list from OpenWRT repositories
opkg update

# Install USB Attached SCSI kernel module
opkg install kmod-usb-storage-uas        # This will install kmod-usb-storage, too

# Load the UAS driver (kernel module)
modprobe uas

# List SCSI volumes
grep sd /proc/partitions

# Show a HEX dump of the beginning of the disk:
hexdump -C /dev/sda|less|head -30


# fstab management
```sh
opkg install block-mount
block info
block info | grep "/dev/sd"
```

Mount the disk at boot
```sh
block detect | uci import fstab
uci set fstab.@mount[-1].enabled='1'
uci set fstab.@mount[-1].options='compress=zstd'
uci set fstab.@global[0].check_fs='1'
uci commit fstab
uci show fstab
service fstab boot
```



# Install NTFS drivers:
#opkg install ntfs-3g-utils

# Install btrfs utils and kernel module
opkg install btrfs-progs

# Format btrfs volume
mkfs.btrfs -L Calin /dev/dm-0
root@MiniMot:~# mkfs.btrfs -L Calin /dev/dm-0
btrfs-progs v6.0.1
See http://btrfs.wiki.kernel.org for more information.

NOTE: several default settings have changed in version 5.15, please make sure
      this does not affect your deployments:
      - DUP for metadata (-m dup)
      - enabled no-holes (-O no-holes)
      - enabled free-space-tree (-R free-space-tree)

Label:              Calin
UUID:               0aca9e39-bc9e-4ef9-8fe6-a2c184d7d9a5
Node size:          16384
Sector size:        4096
Filesystem size:    3.64TiB
Block group profiles:
  Data:             single            8.00MiB
  Metadata:         DUP               1.00GiB
  System:           DUP               8.00MiB
SSD detected:       no
Zoned device:       no
Incompat features:  extref, skinny-metadata, no-holes
Runtime features:   free-space-tree
Checksum:           crc32c
Number of devices:  1
Devices:
   ID        SIZE  PATH
    1     3.64TiB  /dev/dm-0

root@MiniMot:~#

# Create the mountpoint:
mkdir /mnt/dm-0

# Mount the btrfs partition:
mount -o compress=zstd /dev/dm-0 /mnt/dm-0/

# Install Samba:
opkg install luci-app-samba4




# Disk encryption - https://wiki.archlinux.org/title/Data-at-rest_encryption
## Destroy all data on the disk
wipefs -a /dev/sda

## Install cryptsetup and Kernel modules
opkg install kmod-crypto-ecb kmod-crypto-xts kmod-crypto-seqiv kmod-crypto-misc kmod-crypto-user cryptsetup
modprobe crypto-ecb
modprobe crypto-seqiv
modprobe crypto-user
modprobe crypto-xts

## Create the GPT disklabel with one single partition of type "8308 Linux dm-crypt CA7D7CCB-63ED-4C53-861C-1742536059CC". The partition will cover the whole disk.
sgdisk --new=1:0:0 --typecode=1:8309 --print /dev/sda

## Test encryption speed - to determine hardware acceleration support

cryptsetup benchmark
```
root@MiniMot:~# cryptsetup benchmark
# Tests are approximate using memory only (no storage IO).
PBKDF2-sha1        32800 iterations per second for 256-bit key
PBKDF2-sha256      61593 iterations per second for 256-bit key
PBKDF2-sha512        N/A
PBKDF2-ripemd160     N/A
PBKDF2-whirlpool   18649 iterations per second for 256-bit key
argon2i       4 iterations, 78112 memory, 4 parallel threads (CPUs) for 256-bit key (requested 2000 ms time)
argon2id      4 iterations, 79921 memory, 4 parallel threads (CPUs) for 256-bit key (requested 2000 ms time)
#     Algorithm |       Key |      Encryption |      Decryption
        aes-cbc        128b        34.2 MiB/s        36.6 MiB/s
    serpent-cbc        128b        22.5 MiB/s        25.9 MiB/s
    twofish-cbc        128b        30.5 MiB/s        33.3 MiB/s
        aes-cbc        256b        27.0 MiB/s        28.9 MiB/s
    serpent-cbc        256b        22.5 MiB/s        25.9 MiB/s
    twofish-cbc        256b        30.3 MiB/s        33.4 MiB/s
        aes-xts        256b        35.9 MiB/s        36.7 MiB/s
    serpent-xts        256b        23.7 MiB/s        26.2 MiB/s
    twofish-xts        256b        32.1 MiB/s        34.3 MiB/s
        aes-xts        512b        28.3 MiB/s        29.0 MiB/s
    serpent-xts        512b        23.7 MiB/s        26.3 MiB/s
    twofish-xts        512b        31.9 MiB/s        34.0 MiB/s
```

```
[root@laptop-rh ~]# cryptsetup benchmark
# Tests are approximate using memory only (no storage IO).
PBKDF2-sha1      1517476 iterations per second for 256-bit key
PBKDF2-sha256    2068197 iterations per second for 256-bit key
PBKDF2-sha512    1560380 iterations per second for 256-bit key
PBKDF2-ripemd160  866591 iterations per second for 256-bit key
PBKDF2-whirlpool  695342 iterations per second for 256-bit key
argon2i       8 iterations, 1048576 memory, 4 parallel threads (CPUs) for 256-bit key (requested 2000 ms time)
argon2id      8 iterations, 1048576 memory, 4 parallel threads (CPUs) for 256-bit key (requested 2000 ms time)
#     Algorithm |       Key |      Encryption |      Decryption
        aes-cbc        128b      1230.1 MiB/s      3616.0 MiB/s
    serpent-cbc        128b       106.2 MiB/s       767.4 MiB/s
    twofish-cbc        128b       245.5 MiB/s       400.7 MiB/s
        aes-cbc        256b       939.9 MiB/s      2958.2 MiB/s
    serpent-cbc        256b       106.1 MiB/s       760.7 MiB/s
    twofish-cbc        256b       246.1 MiB/s       385.4 MiB/s
        aes-xts        256b      3393.0 MiB/s      3411.6 MiB/s
    serpent-xts        256b       661.2 MiB/s       654.6 MiB/s
    twofish-xts        256b       358.7 MiB/s       361.8 MiB/s
        aes-xts        512b      2770.7 MiB/s      2788.9 MiB/s
    serpent-xts        512b       651.4 MiB/s       646.7 MiB/s
    twofish-xts        512b       354.8 MiB/s       358.8 MiB/s
```

## Create the LUKS partition
cryptsetup luksFormat /dev/sda1

## Attach the encrypted block device
cryptsetup open /dev/sda1

