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

# mount point for installation
mountpoint_chroot="/mnt/fedora"

# mount options
btrfs_mount_options="compress=zstd:1"
efi_mount_options="umask=0077,shortname=winnt"

echo "$fedora_version" > /dev/null 2>&1
echo "$efi_size" > /dev/null 2>&1
echo "$efi_label" > /dev/null 2>&1
echo "$btrfs_label" > /dev/null 2>&1
echo "$mountpoint_chroot" > /dev/null 2>&1
echo "$btrfs_mount_options" > /dev/null 2>&1
