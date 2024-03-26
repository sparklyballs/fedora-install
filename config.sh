#!/bin/bash

set -euf -o pipefail

# get fedora version
source /etc/os-release
fedora_version="${VERSION_ID}"

# partition size for efi
efi_size="640M"

# labels for partitions
efi_label="EFI"
btrfs_label="FEDORA"

# mount options
mountpoint_chroot="/mnt/fedora"
mount_options="rw,commit=120,compress-force=zstd:1,discard=async,noatime,space_cache=v2,ssd"
fstab_options="${mount_options},x-systemd.device-timeout=0"


echo "$fedora_version" > /dev/null 2>&1
echo "$efi_size" > /dev/null 2>&1
echo "$efi_label" > /dev/null 2>&1
echo "$btrfs_label" > /dev/null 2>&1
echo "$mountpoint_chroot" > /dev/null 2>&1
echo "$mount_options" > /dev/null 2>&1
echo "$fstab_options" > /dev/null 2>&1

