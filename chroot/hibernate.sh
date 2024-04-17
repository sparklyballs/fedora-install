#!/bin/bash
set -uf -o pipefail

# import variables from install script
swap_size=${1}

# configure swap hibernation, if required
if [[ "$swap_size" = *noswap* ]] ; then
:
else

# configure dracut for resume and regenerate initramfs

cat <<-EOF | tee /etc/dracut.conf.d/resume.conf
add_dracutmodules+=" resume "
EOF

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

# install script to reset swap offset after btrfs scrub/balance etc
install -D -m 0755 -o root /root/swap/swap_offset /usr/bin

# set systemd services for hibernation
install -D -m 0644 -o root /root/swap/hibernate-preparation.service /etc/systemd/system
install -D -m 0644 -o root /root/swap/hibernate-resume.service /etc/systemd/system

systemctl enable hibernate-preparation.service
systemctl enable hibernate-resume.service

mkdir -p \
	/etc/systemd/system/systemd-logind.service.d \
	/etc/systemd/system/systemd-hibernate.service.d

install -D -m 0644 -o root /root/swap/override.conf /etc/systemd/system/systemd-logind.service.d
install -D -m 0644 -o root /root/swap/override.conf /etc/systemd/system/systemd-hibernate.service.d


# set systemd service for suspend-then-hibernate
install -D -m 0644 -o root /root/swap/suspend-to-hibernate.service /etc/systemd/system

install -D -m 0644 -o root /root/swap/suspend.target /etc/systemd/system
systemctl enable suspend-to-hibernate

fi

# selinux fix for swapfile to survive relabelling so hibernation works
semanage fcontext -a -t swapfile_t /swap/swapfile
restorecon -v /swap/swapfile

# regenerate initramfs and grub config
dracut -f --kver "$(rpm -q kernel | sed 's/^[^-]*-//')"
grub2-mkconfig -o /boot/grub2/grub.cfg
