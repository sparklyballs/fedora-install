#!/bin/bash
set -uf -o pipefail

# import variables from install script
grub_packages=${1}
kernel_parameters=${2}
max_resolution=${3}
microcode=${4}
nvidia_kernel=${5}
video_card_manufacturers=${6}

# read variables into arrays
IFS=' ' read -r -a grub_packages_array <<< "$grub_packages"
IFS=' ' read -r -a kernel_parameters_array <<< "$kernel_parameters"
IFS=' ' read -r -a nvidia_kernel_array <<< "$nvidia_kernel"
IFS=' ' read -r -a video_card_manufacturers_array <<< "$video_card_manufacturers"

# configure intel wifi options
lsmod | if grep -q -wi "iwlwifi"; then
cat > /etc/modprobe.d/iwlwifi.conf <<'EOF'
options iwlmvm power_scheme=2
# options iwlwifi amsdu_size=2
# options iwlwifi disable_11ax=1
# options iwlwifi disable_11be=1
options iwlwifi power_save=0
# options iwlwifi swcrypto=0
# options iwlwifi uapsd_disable=1
EOF
cat > /etc/udev/rules.d/81-wifi-powersave.rules <<'EOF'
ACTION=="add", SUBSYSTEM=="net", KERNEL=="wl*", RUN+="/usr/bin/iw dev $name set power_save off"
EOF
fi

# harden network config
cat > /etc/sysctl.d/90-network.conf <<'EOF'
# Do not act as a router
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# SYN flood protection
net.ipv4.tcp_syncookies = 1

# Disable ICMP redirect
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Do not send ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
EOF

# install grub theme
git clone https://github.com/xenlism/grub-themes /tmp/grub-themes || exit
sed -i 's#/boot/efi/EFI/fedora/grub.cfg#/boot/grub2/grub.cfg#g' "/tmp/grub-themes/xenlism-grub-$max_resolution-Fedora/install.sh"
cd "/tmp/grub-themes/xenlism-grub-$max_resolution-Fedora" || exit
./install.sh

# configure kernel parameters
if [[ "${microcode}" = *amd-ucode* ]] ; then \
kernel_parameters_array+=( "amd_pstate=active" )
fi

# sort grub parameters array alphabetically
readarray -td '' kernel_parameters_array < <(printf '%s\0' "${kernel_parameters_array[@]}" | sort -rz)
readarray -td '' nvidia_kernel_array < <(printf '%s\0' "${nvidia_kernel_array[@]}" | sort -rz)

for param in "${kernel_parameters_array[@]}" ; do
sed -i "s#${param}# #g" /etc/default/grub
grep -qF "${param}" /etc/default/grub || sed -i -e "s#\(GRUB_CMDLINE_LINUX=\"\)#\1${param} #g" /etc/default/grub
done

if printf '%s\0' "${video_card_manufacturers_array[@]}" | grep -Fxqz -- 'nvidia'; then
for param in "${nvidia_kernel_array[@]}" ; do
sed -i "s#${param}# #g" /etc/default/grub
grep -qF "${param}" /etc/default/grub || sed -i -e "s#\(GRUB_CMDLINE_LINUX=\"\)#\1${param} #g" /etc/default/grub
done
fi

# strip any extra spaces from grub config
sed -i -e "s/[[:space:]]\+/ /g" /etc/default/grub
sed -i -e "s/[[:space:]]\"/\"/g" /etc/default/grub

# clear grub config and reinstall grub packages
rm -f \
/boot/grub2/grub.cfg \
/boot/efi/EFI/fedora/grub.cfg

dnf reinstall -y \
"${grub_packages_array[@]}"

# reconfigure the grub.cfg for btrfs etc...
sed -i '1i set btrfs_relative_path="yes"' /boot/efi/EFI/fedora/grub.cfg
sed -i 's/--root-dev-only//g' /boot/efi/EFI/fedora/grub.cfg
grub2-mkconfig -o /boot/grub2/grub.cfg

# regenerate dracut
cat << EOF > /etc/dracut.conf.d/99-my-flags.conf
omit_dracutmodules+=" biosdevname busybox connman dmraid memstrack network-legacy network-wicked rngd systemd-networkd "
EOF

cat > /etc/dracut.conf.d/00-options.conf <<EOF
hostonly="yes"
early_microcode="yes"
compress="zstd"
EOF

dracut -f --kver "$(rpm -q kernel | sed 's/^[^-]*-//')"

# enable services
for drv in qemu interface network nodedev nwfilter secret storage; do \
        systemctl enable virt${drv}d.service; \
        systemctl enable virt${drv}d{,-ro,-admin}.socket; \
done

systemctl enable fstrim.timer

# fix selinux
fixfiles onboot
