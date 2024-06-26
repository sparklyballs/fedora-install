#!/bin/bash
set -uf -o pipefail

# import variables from install script
kernel_parameters=${1}
microcode=${2}
nvidia_kernel=${3}
video_card_manufacturers=${4}

# read variables into arrays
IFS=' ' read -r -a kernel_parameters_array <<< "$kernel_parameters"
IFS=' ' read -r -a nvidia_kernel_array <<< "$nvidia_kernel"
IFS=' ' read -r -a video_card_manufacturers_array <<< "$video_card_manufacturers"

# configure intel wifi powersave
lsmod | if grep -q -wi "iwlwifi"; then
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf <<'EOF'
[connection]
wifi.powersave = 2
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
mkdir -p /usr/share/grub/themes/fedora
curl -o \
/tmp/theme.tar -L \
"https://github.com/AdisonCavani/distro-grub-themes/raw/master/themes/fedora.tar"
tar xf \
/tmp/theme.tar -C \
/usr/share/grub/themes/fedora
grep -qF "/usr/share/grub/themes/fedora/theme.txt" /etc/default/grub || echo -e 'GRUB_THEME="/usr/share/grub/themes/fedora/theme.txt"' >> /etc/default/grub

# configure kernel parameters
if [[ "${microcode}" = *amd-ucode* ]] ; then \
kernel_parameters_array+=( "amd_pstate=guided" )
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

grub2-mkconfig -o /boot/grub2/grub.cfg

# configure dracut
cat << EOF > /etc/dracut.conf.d/99-my-flags.conf
omit_dracutmodules+=" biosdevname busybox connman dmraid memstrack network-legacy network-wicked rngd systemd-networkd "
EOF

cat > /etc/dracut.conf.d/00-options.conf <<EOF
hostonly="yes"
early_microcode="yes"
compress="zstd"
EOF

# enable services
for drv in qemu interface network nodedev nwfilter secret storage; do \
        systemctl enable virt${drv}d.service; \
        systemctl enable virt${drv}d{,-ro,-admin}.socket; \
done

systemctl enable fstrim.timer
