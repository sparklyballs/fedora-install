#!/bin/bash
# shellcheck disable=SC2154,SC1091

set -euf -o pipefail

# install_base_folder=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
. "${install_base_folder}/config.sh"

# make install mountpoint directory
mkdir -p "${mountpoint_chroot}"

# cleanup old installs
umount -A --recursive "${mountpoint_chroot}" || :

# run wizard script
. "${install_base_folder}/base/wizard.sh"

clear

# make partitions

clear
printf "####################	setting up partitions	####################\n"
sgdisk -Z "${root_device}"
sgdisk \
	-n=1:0:+"${efi_size}"		-t=1:ef00	-c1:"${efi_label}" \
	-n=2:0:0			-t=2:8300	-c2:"${btrfs_label}" \
	"${root_device}"

sleep 3
partprobe -s "${root_device}"
sleep 3

# format partitions
mkfs.fat	-F 32	-n "${efi_label}"	/dev/disk/by-partlabel/"${efi_label}"
mkfs.btrfs	-f	-L "${btrfs_label}"	/dev/disk/by-partlabel/"${btrfs_label}"

udevadm trigger

mount -o "${mount_options}" /dev/disk/by-partlabel/"${btrfs_label}" "${mountpoint_chroot}"
restorecon -RF "${mountpoint_chroot}"


# mount efi partition
mkdir -p "${mountpoint_chroot}/boot/efi"
mount /dev/disk/by-partlabel/"${efi_label}" "${mountpoint_chroot}/boot/efi"

# create btrfs subvolumes
if [[ "$swap_size" = *noswap* ]] ; then
:
else
subvolumes+=( "swap" )
fi

# sort btrfs subvolume array alphabetically
readarray -td '' subvolumes < <(printf '%s\0' "${subvolumes[@]}" | sort -z)

# create btrfs subvolumes
mkdir -p "${mountpoint_chroot}/var/lib/libvirt"

for dir in "${subvolumes[@]}" ; do
btrfs subvolume create "${mountpoint_chroot}/${dir}"
done

# permisions
chmod 1777 "${mountpoint_chroot}/var/tmp"
chattr -R +C "${mountpoint_chroot}/var/lib/libvirt/images"

# install fedora base
dnf --releasever="${fedora_version}" --installroot="${mountpoint_chroot}" install -y basesystem

# configure bind mounts for chroot
for dir in sys dev proc ; do
	mount --rbind "/${dir}" "${mountpoint_chroot}/${dir}"
	mount --make-rslave "${mountpoint_chroot}/${dir}"
done

# install minimal environment and tools for chroot
dnf --releasever="${fedora_version}" --installroot="${mountpoint_chroot}" install --best --setopt=install_weak_deps=False -y \
"${base_packages[@]}"

# copy host resolv conf to our install
rm -f "${mountpoint_chroot}/etc/resolv.conf"
cp /etc/resolv.conf "${mountpoint_chroot}/etc/"

# set locales and keymaps etc
systemd-firstboot --root="${mountpoint_chroot}" \
    --timezone=Europe/London \
    --locale=en_GB.UTF-8 \
    --keymap=gb \
    --hostname="${hostname}" \
    --setup-machine-id

cat <<'EOF' >> "${mountpoint_chroot}/etc/vconsole.conf"
KEYMAP=gb
FONT=eurlatgr
EOF

mkdir -p "${mountpoint_chroot}/etc/X11/xorg.conf.d"

cat <<'EOF' >> "${mountpoint_chroot}/etc/X11/xorg.conf.d/00-keyboard.conf"
Section "InputClass"
        Identifier "system-keyboard"
        MatchIsKeyboard "on"
        Option "XkbLayout" "gb"
EndSection
EOF

# configure fstab
efi_uuid="$(grub2-probe --target=fs_uuid "${mountpoint_chroot}"/boot/efi)"
root_uuid="$(grub2-probe --target=fs_uuid "${mountpoint_chroot}")"

printf "%-41s %-24s %-5s %-s %-s\n" \
	"UUID=${efi_uuid}" \
	"/boot/efi" \
	"vfat" \
	"umask=0077,shortname=winnt" \
	"0 0" > "${mountpoint_chroot}/etc/fstab"

printf "%-41s %-24s %-5s %-s %-s\n" \
	"UUID=${root_uuid}" \
	"/" \
	"btrfs" \
	defaults,"${fstab_options}" \
	"0 0" >> "${mountpoint_chroot}/etc/fstab"

for dir in "${subvolumes[@]}" ; do
printf "%-41s %-24s %-5s %-s %-s\n" \
	"UUID=${root_uuid}" \
	"/${dir}" \
	"btrfs" \
	"subvol=${dir},${fstab_options}" \
	"0 0" >> "${mountpoint_chroot}/etc/fstab"
done

