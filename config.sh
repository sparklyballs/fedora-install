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
toplevel_mount_options="ssd,noatime,space_cache=v2,compress=zstd:3"
mount_options="ssd,noatime,space_cache=v2,autodefrag,compress=zstd:3,discard=async"

echo "$fedora_version" > /dev/null 2>&1
echo "$efi_size" > /dev/null 2>&1
echo "$efi_label" > /dev/null 2>&1
echo "$btrfs_label" > /dev/null 2>&1
echo "$mountpoint_chroot" > /dev/null 2>&1
echo "$mount_options" > /dev/null 2>&1
echo "$toplevel_mount_options" > /dev/null 2>&1
