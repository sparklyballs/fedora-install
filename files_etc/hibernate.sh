#!/bin/bash

[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

# set our variables/arrays
username="$(id -nu 1000)"

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

# set permissions on libvirt images folder
setfacl -R -b /var/lib/libvirt/images
setfacl -R -m u:"${username}":rwX /var/lib/libvirt/images
setfacl -m d:u:"${username}":rwx /var/lib/libvirt/images

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

fi
