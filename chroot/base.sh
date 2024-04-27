#!/bin/bash
set -uf -o pipefail

# import variables from install script
copr_repos=${1}
dnf_configure=${2}
fedora_version=${3}
grub_packages=${4}
motherboard_manufacturer=${5}
video_card_manufacturers=${6}

# read variables into arrays
IFS=' ' read -r -a copr_repos_array <<< "$copr_repos"
IFS=' ' read -r -a dnf_configure_array <<< "$dnf_configure"
IFS=' ' read -r -a grub_packages_array <<< "$grub_packages"
IFS=' ' read -r -a video_card_manufacturers_array <<< "$video_card_manufacturers"

# dnf optimising
for param in "${dnf_configure_array[@]}" ; do
grep -qF "${param}" /etc/dnf/dnf.conf || echo "${param}" >> /etc/dnf/dnf.conf
done

# install gnome DE
dnf group install 'Fedora Workstation' -y

# enable repositories
# fedora 3rd party repos
/usr/bin/fedora-third-party enable

if [[ "${#video_card_manufacturers_array[@]}" -gt 1 ]]  ; then
copr_repos_array+=( "sunwire/envycontrol" )
fi

if [[ "$motherboard_manufacturer" = *asus* ]] ; then
copr_repos_array+=( "lukenukem/asus-linux" )
fi

for repo in "${copr_repos_array[@]}" ; do
dnf copr enable -y "${repo}"
done

dnf config-manager --add-repo https://dl.winehq.org/wine-builds/fedora/39/winehq.repo
dnf install -y "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_version}.noarch.rpm"
dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_version}.noarch.rpm"

# clean dnf cache
dnf clean all
dnf makecache

# reinstall polkit
dnf reinstall -y \
polkit

# initial grub configuration
cat <<EOF > /etc/default/grub
GRUB_TIMEOUT=2
GRUB_DISTRIBUTOR="\$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_CMDLINE_LINUX="rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
SUSE_BTRFS_SNAPSHOT_BOOTING="true"
EOF

grub2-mkconfig -o /boot/grub2/grub.cfg

# reinstall packages to rebuild grub and loader entries
rm -f \
/boot/grub2/grub.cfg \
/boot/efi/EFI/fedora/grub.cfg \
/boot/loader/entries/* \
/boot/*-rescue-*

kernel-install add "$(rpm -q kernel | sed 's/^[^-]*-//')" "/lib/modules/$(rpm -q kernel | sed 's/^[^-]*-//')/vmlinuz"

dnf reinstall -y \
"${grub_packages_array[@]}"

# selinux fixes for grub config files
semanage fcontext -a -t boot_t /boot/grub2/grub.cfg
restorecon -v /boot/grub2/grub.cfg
semanage fcontext -a -t boot_t /boot/efi/EFI/fedora/grub.cfg
restorecon -v /boot/efi/EFI/fedora/grub.cfg

# fix fedora grub.cfg
grep -qF 'set btrfs_relative_path="yes"' /boot/efi/EFI/fedora/grub.cfg || sed -i '1i set btrfs_relative_path="yes"' /boot/efi/EFI/fedora/grub.cfg
sed -i 's/--root-dev-only//g' /boot/efi/EFI/fedora/grub.cfg
# shellcheck disable=SC2016
sed -i 's#set prefix=.*#set prefix=($dev)/boot/grub2#g' /boot/efi/EFI/fedora/grub.cfg
