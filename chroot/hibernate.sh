#!/bin/bash
set -uf -o pipefail

setenforce 0

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

# enable services for hibernate and suspend to hibernate
systemctl enable hibernate-preparation.service
systemctl enable hibernate-resume.service
systemctl enable suspend-to-hibernate

# selinux fix for swapfile to survive relabelling so hibernation works
semanage fcontext -a -t swapfile_t /swap/swapfile
restorecon -v /swap/swapfile

# regenerate initramfs and grub config
dracut -f --kver "$(rpm -q kernel | sed 's/^[^-]*-//')"
grub2-mkconfig -o /boot/grub2/grub.cfg
