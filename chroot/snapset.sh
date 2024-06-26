#!/bin/bash
set -uf -o pipefail

# import variables from install script
snapper_configs=${1}
snapper_packages=${2}

# read variables into arrays
IFS=' ' read -r -a snapper_configs_array <<< "$snapper_configs"
IFS=' ' read -r -a snapper_packages_array <<< "$snapper_packages"

# fix sparse file error
grub2-editenv - unset menu_auto_hide

# install packages
dnf install -y \
"${snapper_packages_array[@]}"

# setup snapper , deleting existing folders and remounting etc.
umount /.snapshots
rm -r /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
chmod 750 /.snapshots

# configure snapper
for conf in "${snapper_configs_array[@]}" ; do
snapper --no-dbus -c root set-config "${conf}"
done

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

# configure system for snapper
grep -qF ".snapshots" /etc/updatedb.conf || echo 'PRUNENAMES = ".snapshots"' | tee -a /etc/updatedb.conf
grep -qF "SUSE_BTRFS_SNAPSHOT_BOOTING" /etc/default/grub || echo 'SUSE_BTRFS_SNAPSHOT_BOOTING="true"' | tee -a /etc/default/grub

# fix for tpm error when booting snapshots
cat <<EOF > /etc/grub.d/02_tpm
#!/usr/bin/sh -e
echo "rmmod tpm"
EOF
chmod +x /etc/grub.d/02_tpm

# strip any extra spaces from grub config
sed -i -e "s/[[:space:]]\+/ /g" /etc/default/grub
sed -i -e "s/[[:space:]]\"/\"/g" /etc/default/grub

grub2-mkconfig -o /boot/grub2/grub.cfg

# regenerate initramfs
dracut -f --kver "$(rpm -q kernel | sed 's/^[^-]*-//')"

# selinux fix
fixfiles onboot

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
