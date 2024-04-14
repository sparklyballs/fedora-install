#!/bin/bash
set -uf -o pipefail

# set selinux to permissive
setenforce 0

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

# install grub-btrfs
dnf install -y \
	gcc \
	gcc-c++ \
	git \
	make \
	inotify-tools

# install btrfs-grub
git clone https://github.com/Antynea/grub-btrfs /tmp/grub-btrfs
sed -i \
	-e '/#GRUB_BTRFS_SNAPSHOT_KERNEL/a GRUB_BTRFS_SNAPSHOT_KERNEL_PARAMETERS="systemd.volatile=state"' \
	-e '/#GRUB_BTRFS_GRUB_DIRNAME/a GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"' \
	-e '/#GRUB_BTRFS_MKCONFIG=/a GRUB_BTRFS_MKCONFIG=/sbin/grub2-mkconfig'\
	-e '/#GRUB_BTRFS_SCRIPT_CHECK=/a GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check' \
/tmp/grub-btrfs/config

cd /tmp/grub-btrfs || exit
make install

# remove grub config and loader entries
# rm -f \
#	/boot/grub2/grub.cfg \
#	/boot/efi/EFI/fedora/grub.cfg \
#	/boot/loader/entries/*

# reinstall grub packages and kernel-core
# dnf reinstall -y \
# "${grub_packages_array[@]}" \
# kernel-core

# configure grub for subvol booting and regenerate grub
# configure system for snapper
grep -qF ".snapshots" /etc/updatedb.conf || echo 'PRUNENAMES = ".snapshots"' | tee -a /etc/updatedb.conf
grep -qF "SUSE_BTRFS_SNAPSHOT_BOOTING" /etc/default/grub || echo 'SUSE_BTRFS_SNAPSHOT_BOOTING="true"' | tee -a /etc/default/grub
# sed -i '1i set btrfs_relative_path="yes"' /boot/efi/EFI/fedora/grub.cfg
# sed -i 's/--root-dev-only//g' /boot/efi/EFI/fedora/grub.cfg
# sed -i.bak 's#rootflags=subvol=${rootsubvol}##g' /etc/grub.d/10_linux
# sed -i.bak 's#rootflags=subvol=${rootsubvol}##g' /etc/grub.d/20_linux_xen

grub2-mkconfig -o /boot/grub2/grub.cfg

# regenerate initramfs
dracut -f --kver "$(rpm -q kernel | sed 's/^[^-]*-//')"

# enable snapper services
systemctl enable grub-btrfsd.service
sed -i 's/OnUnitActiveSec=.*/OnUnitActiveSec=3h/g' /lib/systemd/system/snapper-cleanup.timer
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# create first snapshot and set as default
mkdir -v /.snapshots/1
bash -c "cat > /.snapshots/1/info.xml" <<EOF
<?xml version="1.0"?>
 <snapshot>
   <type>single</type>
   <num>1</num>
   <date>$(date -u +"%F %T")</date>
   <description>root subvolume</description>
 </snapshot>
EOF

btrfs subvolume snapshot / /.snapshots/1/snapshot
snapshot_id="$(btrfs inspect-internal rootid /.snapshots/1/snapshot)"
btrfs subvolume set-default "${snapshot_id}" /

