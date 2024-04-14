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
install -D -m 0755 -o root "${install_base_folder}/chroot/setup.sh" "${mountpoint_chroot}/root"

# install get iso and grubfix scripts
install -D -m 0755 -o root "${install_base_folder}/files_etc/get_archiso" "${mountpoint_chroot}/usr/bin"
install -D -m 0755 -o root "${install_base_folder}/files_etc/get_fediso" "${mountpoint_chroot}/usr/bin"
install -D -m 0755 -o root "${install_base_folder}/files_etc/grub_fix" "${mountpoint_chroot}/usr/bin"

# install forkboard and snapshot scripts
install -D -m 0755 -o root "${install_base_folder}/files_etc/forkboard.sh" "${mountpoint_chroot}/root"
install -D -m 0755 -o root "${install_base_folder}/files_etc/snapshot.sh" "${mountpoint_chroot}/root"

# run chroot scripts
chroot "${mountpoint_chroot}" /root/base.sh \
	"${copr_repos[*]}" \
	"${dnf_configure[*]}" \
	"${fedora_version}" \
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
	"${max_resolution}" \
	"${microcode}" \
	"${nvidia_kernel[*]}" \
	"${video_card_manufacturers[*]}"

chroot "${mountpoint_chroot}" /root/setup.sh \
	"${grub_packages[*]}"

# cleanup scripts from root
rm -f \
"${mountpoint_chroot}/root/applications.sh" \
"${mountpoint_chroot}/root/base.sh" \
"${mountpoint_chroot}/root/configure.sh" \
"${mountpoint_chroot}/root/setup.sh"
