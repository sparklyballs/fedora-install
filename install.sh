#!/bin/bash
# shellcheck disable=SC1091,SC2154

[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

set -uf -o pipefail

# run config script
install_base_folder=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
. "${install_base_folder}/config.sh"

# source packages and vars list
. "${install_base_folder}/files_etc/packages_vars"

# configure dnf.conf
for param in "${dnf_configure[@]}" ; do
grep -qF "${param}" /etc/dnf/dnf.conf || echo "${param}" >> /etc/dnf/dnf.conf
done

# install required host packages
dnf install --best -y \
	"${host_packages[@]}" \
	2> /dev/null

# run install script
. "${install_base_folder}/base/install.sh"

# install installation script(s)
install -D -m 0755 -o root "${install_base_folder}/chroot/applications.sh" "${mountpoint_chroot}/root"
install -D -m 0755 -o root "${install_base_folder}/chroot/base.sh" "${mountpoint_chroot}/root"
install -D -m 0755 -o root "${install_base_folder}/chroot/configure.sh" "${mountpoint_chroot}/root"
install -D -m 0755 -o root "${install_base_folder}/chroot/hibernate.sh" "${mountpoint_chroot}/root"
install -D -m 0755 -o root "${install_base_folder}/chroot/snapset.sh" "${mountpoint_chroot}/root"


# install get iso, grubfix and rescuefix scripts
install -D -m 0755 -o root "${install_base_folder}/files_etc/get_archiso" "${mountpoint_chroot}/usr/bin"
install -D -m 0755 -o root "${install_base_folder}/files_etc/get_fediso" "${mountpoint_chroot}/usr/bin"
install -D -m 0755 -o root "${install_base_folder}/files_etc/grub_fix" "${mountpoint_chroot}/usr/bin"
install -D -m 0755 -o root "${install_base_folder}/files_etc/rescue_fix" "${mountpoint_chroot}/usr/bin"


# run chroot scripts
chroot "${mountpoint_chroot}" /root/base.sh \
	"${copr_repos[*]}" \
	"${dnf_configure[*]}" \
	"${fedora_version}" \
	"${grub_packages[*]}" \
	"${motherboard_manufacturer}" \
	"${video_card_manufacturers[*]}"

#chroot "${mountpoint_chroot}" /root/applications.sh \
#	"${app_packages[*]}" \
#	"${flatpak_packages[*]}" \
#	"${gaming_packages[*]}" \
#	"${motherboard_manufacturer}" \
#	"${video_card_manufacturers[*]}" \
#	"${virtualization_packages[*]}"

chroot "${mountpoint_chroot}" /root/configure.sh \
	"${kernel_parameters[*]}" \
	"${microcode}" \
	"${nvidia_kernel[*]}" \
	"${video_card_manufacturers[*]}"

# configure swap hibernation if required
if [[ "$swap_size" = *noswap* ]] ; then
:
else
install -D -m 0755 -o root "${install_base_folder}/files_etc/swap/swap_offset" "${mountpoint_chroot}/usr/bin"
install -D -m 0644 -o root "${install_base_folder}/files_etc/swap/suspend-to-hibernate.service" "${mountpoint_chroot}/etc/systemd/system"
install -D -m 0644 -o root "${install_base_folder}/files_etc/swap/suspend.target" "${mountpoint_chroot}/etc/systemd/system"

chroot "${mountpoint_chroot}" /root/hibernate.sh
fi

chroot "${mountpoint_chroot}" /root/snapset.sh \
	"${snapper_configs[*]}" \
	"${snapper_packages[*]}"

# cleanup scripts from root
rm -f \
"${mountpoint_chroot}/root/applications.sh" \
"${mountpoint_chroot}/root/base.sh" \
"${mountpoint_chroot}/root/configure.sh" \
"${mountpoint_chroot}/root/hibernate.sh" \
"${mountpoint_chroot}/root/snapset.sh"
