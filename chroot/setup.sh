#!/bin/bash
set -uf -o pipefail

# import variables from install script
grub_packages=${1}

# read variables into arrays
IFS=' ' read -r -a grub_packages_array <<< "$grub_packages"

# setup snapper , deleting existing folders and remounting etc.
umount /.snapshots
rm -r /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
chmod 750 /.snapshots

# remove grub config and loader entries
rm -f \
	/boot/grub2/grub.cfg \
	/boot/efi/EFI/fedora/grub.cfg \
	/boot/loader/entries/*

# reinstall grub packages and kernel-core
dnf reinstall -y \
"${grub_packages_array[@]}" \
kernel-core

# configure grub for subvol booting and regenerate grub
sed -i '1i set btrfs_relative_path="yes"' /boot/efi/EFI/fedora/grub.cfg
sed -i 's/--root-dev-only//g' /boot/efi/EFI/fedora/grub.cfg
sed -i.bak 's#rootflags=subvol=${rootsubvol}##g' /etc/grub.d/10_linux
sed -i.bak 's#rootflags=subvol=${rootsubvol}##g' /etc/grub.d/20_linux_xen

grub2-mkconfig -o /boot/grub2/grub.cfg

# regenerate initramfs
dracut -f --kver "$(rpm -q kernel | sed 's/^[^-]*-//')"
