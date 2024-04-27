#!/bin/bash
set -uf -o pipefail

# import variables from install script
app_packages=${1}
flatpak_packages=${2}
gaming_packages=${3}
motherboard_manufacturer=${4}
video_card_manufacturers=${5}
virtualization_packages=${6}

# read variables into arrays
IFS=' ' read -r -a app_packages_array <<< "$app_packages"
IFS=' ' read -r -a flatpak_packages_array <<< "$flatpak_packages"
IFS=' ' read -r -a gaming_packages_array <<< "$gaming_packages"
IFS=' ' read -r -a video_card_manufacturers_array <<< "$video_card_manufacturers"
IFS=' ' read -r -a virtualization_packages_array <<< "$virtualization_packages"

# install general app packages
dnf install -y \
"${app_packages_array[@]}"

# install msttcore fonts
rpm -i https://downloads.sourceforge.net/project/mscorefonts2/rpms/msttcore-fonts-installer-2.6-1.noarch.rpm

# install gaming packages
dnf swap wine winehq-staging -y
dnf install --allowerasing --best -y \
"${gaming_packages_array[@]}"

# install virtualization packages
dnf install -y \
"${virtualization_packages_array[@]}"

# install asusctl/envycontrol packages
if [[ "$motherboard_manufacturer" = *asus* ]] ; then
dnf install -y \
asusctl \
asusctl-rog-gui
fi

if [[ "${#video_card_manufacturers_array[@]}" -gt 1 ]] ; then
dnf install -y \
python3-envycontrol
fi

# install codecs
dnf swap -y ffmpeg-free ffmpeg --allowerasing
dnf groupupdate multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin -y
dnf groupupdate sound-and-video -y
dnf install -y gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-plugin-openh264 gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel
dnf install -y lame* --exclude=lame-devel
dnf group upgrade --with-optional Multimedia -y
dnf install -y gstreamer1-plugin-openh264
dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld
dnf swap -y mesa-vdpau-drivers mesa-vdpau-drivers-freeworld
dnf swap -y mesa-va-drivers.i686 mesa-va-drivers-freeworld.i686
dnf swap -y mesa-vdpau-drivers.i686 mesa-vdpau-drivers-freeworld.i686
dnf install -y --allowerasing ffmpeg-devel libavcodec-freeworld
dnf install -y vdpauinfo

# install nvidia drivers
if printf '%s\0' "${video_card_manufacturers_array[@]}" | grep -Fxqz -- 'nvidia'; then
dnf install -y \
akmod-nvidia \
xorg-x11-drv-nvidia-cuda
dnf install -y \
nvidia-gpu-firmware \
nvidia-vaapi-driver
fi

# install better fonts
dnf install fontconfig-font-replacements --disableexcludes=all -y
dnf install fontconfig-enhanced-defaults --disableexcludes=all -y

# install flatpak packages
flatpak install -y \
"${flatpak_packages_array[@]}"
