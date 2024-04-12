#!/bin/bash

[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# set our variables/arrays
username="$(id -nu 1000)"

snapper_configs=(
"ALLOW_GROUPS=wheel"
"SYNC_ACL=yes"
"TIMELINE_CREATE=yes"
"TIMELINE_MIN_AGE=1800"
"NUMBER_LIMIT=30"
"TIMELINE_LIMIT_HOURLY=7"
"TIMELINE_LIMIT_DAILY=5"
"TIMELINE_LIMIT_WEEKLY=0"
"TIMELINE_LIMIT_MONTHLY=0"
"TIMELINE_LIMIT_YEARLY=0"
)

calculate_swap () {
	mem_calculated=$(free --giga | grep Mem: | awk '{print $2}')
	mem_calculated=$(( (mem_calculated + 1) & ~1 ))
	case $((
	(mem_calculated >= 0 && mem_calculated <= 2)    * 1 +
	(mem_calculated >  2 && mem_calculated <= 8)    * 2 +
	(mem_calculated >  8 && mem_calculated <= 64)   * 3 +
	(mem_calculated >  64)				* 4)) in
	(1) swap_size=$(awk "BEGIN {print ($mem_calculated)*3}");;
	(2) swap_size=$(awk "BEGIN {print ($mem_calculated)*2}");;
	(3) swap_size=$(awk "BEGIN {print ($mem_calculated)*1.5}");;
	(4) swap_size="noswap";;
	esac
}
calculate_swap

# fix sparse file error
grub2-editenv - unset menu_auto_hide

# set permissions on libvirt images folder
setfacl -R -b /var/lib/libvirt/images
setfacl -R -m u:"${username}":rwX /var/lib/libvirt/images
setfacl -m d:u:"${username}":rwx /var/lib/libvirt/images

# install required packages
dnf install -y \
btrfs-progs \
inotify-tools \
make \
rsync \
vim

# configure swap hibernation, if required
if [[ "$swap_size" = *noswap* ]] ; then
:
else

# create swapfile
touch /swap/swapfile
chattr +C /swap/swapfile
fallocate --length "${swap_size}G" /swap/swapfile
chmod 600 /swap/swapfile
mkswap /swap/swapfile

# configure dracut for resume and regenerate initramfs

cat <<-EOF | tee /etc/dracut.conf.d/resume.conf
add_dracutmodules+=" resume "
EOF
dracut -f

swap_uuid=$(findmnt -no UUID -T /swap/swapfile)
swap_offset=$(btrfs inspect-internal map-swapfile -r /swap/swapfile)

resume_kernel_params=(
"resume_offset=${swap_offset}"
"resume=UUID=${swap_uuid}"
)

for param in "${resume_kernel_params[@]}" ; do
sed -i "s#${param}# #g" /etc/default/grub
grep -qF "${param}" /etc/default/grub || sed -i -e "s#\(GRUB_CMDLINE_LINUX=\"\)#\1${param} #g" /etc/default/grub
done

# configure script to reset swap offset after btrfs scrub/balance etc
cat <<EOF > /usr/bin/swap_offset
#!/bin/bash

[ "\$UID" -eq 0 ] || exec sudo bash "\$0" "\$@"

swap_offset=\$(btrfs inspect-internal map-swapfile -r /swap/swapfile)

if grep -qF "\${swap_offset}" /etc/default/grub
then
:
else
sed -i "s/resume_offset=[0-9]*/resume_offset=\${swap_offset}/g" /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
fi
EOF

chmod +x /usr/bin/swap_offset

# set systemd services for hibernation
cat <<-EOF | tee /etc/systemd/system/hibernate-preparation.service
[Unit]
Description=Enable swap file and disable zram before hibernate
Before=systemd-hibernate.service

[Service]
User=root
Type=oneshot
ExecStart=/bin/bash -c "/usr/sbin/swapon /swap/swapfile && /usr/sbin/swapoff /dev/zram0"

[Install]
WantedBy=systemd-hibernate.service
EOF

cat <<-EOF | tee /etc/systemd/system/hibernate-resume.service
[Unit]
Description=Disable swap after resuming from hibernation
After=hibernate.target

[Service]
User=root
Type=oneshot
ExecStart=/usr/sbin/swapoff /swap/swapfile

[Install]
WantedBy=hibernate.target
EOF

systemctl enable hibernate-preparation.service
systemctl enable hibernate-resume.service

mkdir -p \
	/etc/systemd/system/systemd-logind.service.d \
	/etc/systemd/system/systemd-hibernate.service.d

cat <<-EOF | tee /etc/systemd/system/systemd-logind.service.d/override.conf
[Service]
Environment=SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1
EOF

cat <<-EOF | tee /etc/systemd/system/systemd-hibernate.service.d/override.conf
[Service]
Environment=SYSTEMD_BYPASS_HIBERNATION_MEMORY_CHECK=1
EOF

# set systemd service for suspend-then-hibernate
cat <<-"EOF" | tee /etc/systemd/system/suspend-to-hibernate.service
[Unit]
Description=Delayed hibernation trigger
Documentation=https://bbs.archlinux.org/viewtopic.php?pid=1420279#p1420279
Documentation=https://wiki.archlinux.org/index.php/Power_management
Before=suspend.target
Conflicts=hibernate.target hybrid-suspend.target
StopWhenUnneeded=true

[Service]
Type=oneshot
RemainAfterExit=yes
Environment="WAKEALARM=/sys/class/rtc/rtc0/wakealarm"

# Important: Here you can set the delay after when we go to hibernate:
Environment="SLEEPLENGTH=+1hour"

ExecStart=-/usr/bin/sh -c 'echo -n "alarm set for "; date +%%s -d$SLEEPLENGTH | tee $WAKEALARM'
ExecStop=-/usr/bin/sh -c '\
  alarm=$(cat $WAKEALARM); \
  now=$(date +%%s); \
  if \[ -z "$alarm" \] || \[ "$now" -ge "$alarm" \]; then \
     echo "hibernate triggered"; \
     systemctl hibernate; \
  else \
     echo "normal wakeup"; \
  fi; \
  echo 0 > $WAKEALARM; \
'

[Install]
WantedBy=sleep.target
EOF

cat <<-EOF | tee /etc/systemd/system/suspend.target
#  SPDX-License-Identifier: LGPL-2.1+
#
#  This file is part of systemd.
#
#  systemd is free software; you can redistribute it and/or modify it
#  under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation; either version 2.1 of the License, or
#  (at your option) any later version.

[Unit]
Description=Suspend
Documentation=man:systemd.special(7)
DefaultDependencies=no
Requires=systemd-suspend.service
After=systemd-suspend.service
StopWhenUnneeded=yes

# Important: Add a dependency to our suspend-to-hibernate service:
Requires=suspend-to-hibernate.service
EOF

systemctl enable suspend-to-hibernate

# end of swap hibernation setup
fi

# install snapper packages
dnf install -y \
	python3-dnf-plugin-snapper \
	snapper

# create snapper configs
umount /.snapshots
rm -r /.snapshots
snapper -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots

# remount everything
mount -va

# configure snapper
for conf in "${snapper_configs[@]}" ; do
snapper -c root set-config "${conf}"
done

# configure system for snapper
grep -qF ".snapshots" /etc/updatedb.conf || echo 'PRUNENAMES = ".snapshots"' | tee -a /etc/updatedb.conf
grep -qF "SUSE_BTRFS_SNAPSHOT_BOOTING" /etc/default/grub || echo 'SUSE_BTRFS_SNAPSHOT_BOOTING="true"' | tee -a /etc/default/grub

grub2-mkconfig -o /boot/grub2/grub.cfg

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

grub2-mkconfig -o /boot/grub2/grub.cfg

# enable snapper services
systemctl enable --now grub-btrfsd.service
sed -i 's/OnUnitActiveSec=.*/OnUnitActiveSec=3h/g' /lib/systemd/system/snapper-cleanup.timer
systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

# strip any extra spaces from grub config
sed -i -e "s/[[:space:]]\+/ /g" /etc/default/grub
sed -i -e "s/[[:space:]]\"/\"/g" /etc/default/grub

# fix for tpm error when booting snapshots
cat <<EOF > /etc/grub.d/02_tpm
#!/usr/bin/sh -e
echo "rmmod tpm"
EOF
chmod +x /etc/grub.d/02_tpm

grub2-mkconfig -o /boot/grub2/grub.cfg

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
