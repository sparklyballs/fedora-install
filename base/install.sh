#!/bin/bash
# shellcheck disable=SC2154,SC1091

set -euf -o pipefail

# install_base_folder=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
. "${install_base_folder}/config.sh"

# cleanup old installs
umount -A --recursive "${mountpoint_chroot}" || :

# run wizard script
. "${install_base_folder}/base/wizard.sh"

clear

# make install mountpoint directory
mkdir -p "${mountpoint_chroot}"

# define function for subvolume permissions
subvol_perms() {
extra_options=""
case $1 in
	@boot)
	extra_options=",nodev,nosuid,noexec"
        ;;
	@home|@root)
        extra_options=",nodev,nosuid"
        ;;
	@var_journal)
        extra_options=",nodatacow"
        ;;
	@var_tmp)
        extra_options=",nodatacow,nodev,nosuid"
        ;;
	@var_accounts|@var_cache|@var_crash|@var_gdm|@var_images|@var_log|@var_machines|@var_portables|@var_spool)
        extra_options=",nodatacow,nodev,nosuid,noexec"
        ;;
        @.snapshots)
        extra_options=""
        ;;
        *)
        extra_options=",nodatacow"
        ;;
esac
}

# make partitions
clear
printf "####################	setting up partitions	####################\n"
wipefs -af "${root_device}"
sgdisk -Zo "${root_device}"
sgdisk \
	-n=1:0:+"${efi_size}"		-t=1:ef00	-c1:"${efi_label}" \
	-n=2:0:0			-t=2:8300	-c2:"${btrfs_label}" \
	"${root_device}"

sleep 3
partprobe -s "${root_device}"
sleep 3

# format partitions
mkfs.fat	-F 32	-n "${efi_label}"		"/dev/disk/by-partlabel/${efi_label}"
mkfs.btrfs	-f	-L "${btrfs_label}"	-n 32k	"/dev/disk/by-partlabel/${btrfs_label}"

udevadm trigger

# mount btrfs volume
mount -o clear_cache,nospace_cache "/dev/disk/by-partlabel/${btrfs_label}" "${mountpoint_chroot}"
restorecon -RF "${mountpoint_chroot}"

btrfs subvolume create "${mountpoint_chroot}/@"

if [[ "$swap_size" = *noswap* ]] ; then
:
else
subvolumes["@swap"]="swap"
fi

for dir in "${!subvolumes[@]}" ; do

btrfs subvolume create "${mountpoint_chroot}/${dir}"

if [[ "${dir}" == "@home" ]] || [[ "${dir}" == "@root" ]] || [[ "${dir}" == "@.snapshots" ]] ; then
:
else
chattr +C "${mountpoint_chroot}/${dir}"
fi
done

btrfs subvolume set-default "$(btrfs subvolume list "${mountpoint_chroot}" | grep "@$" | grep -oP '(?<=ID )[0-9]+')" "${mountpoint_chroot}"

# umount btrfs volume
umount "${mountpoint_chroot}"

# mount (sub)volumes
mount -o "${btrfs_mount_options}" "/dev/disk/by-partlabel/${btrfs_label}" "${mountpoint_chroot}"

for dir in "${!subvolumes[@]}" ; do

subvol_perms "$dir"

if [[ "${dir}" == "@var_journal" ]]; then
:
else
mkdir -p "${mountpoint_chroot}/${subvolumes[$dir]}"
mount -o "subvol=${dir},${btrfs_mount_options}${extra_options}" "/dev/disk/by-partlabel/${btrfs_label}" "${mountpoint_chroot}/${subvolumes[$dir]}"
fi

done

# mount /var/log/journal
mkdir -p "${mountpoint_chroot}/var/log/journal"
mount -o "subvol=@var_journal,${btrfs_mount_options},nodatacow" "/dev/disk/by-partlabel/${btrfs_label}" "${mountpoint_chroot}/var/log/journal"

# mount efi partition
mkdir -p "${mountpoint_chroot}/boot/efi"
mount -o "${efi_mount_options}" "/dev/disk/by-partlabel/${efi_label}" "${mountpoint_chroot}/boot/efi"

# create swapfile
if [[ "$swap_size" = *noswap* ]] ; then
:
else
touch "${mountpoint_chroot}/swap/swapfile"
chattr +C "${mountpoint_chroot}/swap/swapfile"
fallocate --length "${swap_size}G" "${mountpoint_chroot}/swap/swapfile"
chmod 600 "${mountpoint_chroot}/swap/swapfile"
mkswap "${mountpoint_chroot}/swap/swapfile"
fi

# permissions
chmod 1770  "${mountpoint_chroot}/var/lib/gdm"
chmod 0775 "${mountpoint_chroot}/var/lib/AccountsService"

# install fedora base
dnf --releasever="${fedora_version}" --installroot="${mountpoint_chroot}" install -y basesystem

# configure bind mounts for chroot
for dir in sys dev proc ; do
	mount --rbind "/${dir}" "${mountpoint_chroot}/${dir}"
	mount --make-rslave "${mountpoint_chroot}/${dir}"
done

# install minimal environment and tools for chroot
dnf --releasever="${fedora_version}" --installroot="${mountpoint_chroot}" install --best --setopt=install_weak_deps=False -y \
@minimal-environment

dnf --releasever="${fedora_version}" --installroot="${mountpoint_chroot}" install --best -y \
"${base_packages[@]}" \
"${grub_packages[@]}"

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

# generate fstab
efi_uuid="$(grub2-probe --target=fs_uuid "${mountpoint_chroot}/boot/efi")"
root_uuid="$(grub2-probe --target=fs_uuid "${mountpoint_chroot}")"
subvol_name_len="$(printf '/%s\n' "${subvolumes[@]}" | wc -L)"

printf "%-41s %-${subvol_name_len}s %-5s %-s %-s\n" \
	"UUID=${efi_uuid}" \
	"/boot/efi" \
	"vfat" \
	"${efi_mount_options}" \
	"0 2" > "${mountpoint_chroot}/etc/fstab"

printf "%-41s %-${subvol_name_len}s %-5s %-s %-s\n" \
	"UUID=${root_uuid}" \
	"/" \
	"btrfs" \
	"${btrfs_mount_options}" \
	"0 0" >> "${mountpoint_chroot}/etc/fstab"

for dir in "${!subvolumes[@]}" ; do

subvol_perms "$dir"

printf "%-41s %-${subvol_name_len}s %-5s %-s %-s\n" \
	"UUID=${root_uuid}" \
	"/${subvolumes[$dir]}" \
	"btrfs" \
	"subvol=${dir},${btrfs_mount_options}${extra_options}" \
	"0 0" >> "${mountpoint_chroot}/etc/fstab"
done

sort -k2 -o "${mountpoint_chroot}/etc/fstab" "${mountpoint_chroot}/etc/fstab"
