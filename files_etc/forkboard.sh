#!/bin/bash

[ "$UID" -eq 0 ] || exec sudo bash "$0" "$@"

username="$(id -nu 1000)"

# fetch latest build from jenkins instance
wget -O /tmp/forkboard.tar.gz https://ci.sparklyballs.com/job/App-Builds/job/forkboard/lastSuccessfulBuild/artifact/build/forkboard-v1.1.1.tar.gz

# unpack the archive
tar xf /tmp/forkboard.tar.gz -C /tmp

# install (move files) the application
cp -npr  /tmp/forkboard/opt/forkboard /opt/
cp -npr /tmp/forkboard/usr/bin/forkboard /usr/bin/
cp -npr /tmp/forkboard/usr/share/applications/forkboard.desktop /usr/share/applications/
cp -npr /tmp/forkboard/usr/share/icons/hicolor/512x512/apps/forkboard.png /usr/share/icons/hicolor/512x512/apps/

# fetch piavpn run file
piavpn_url=$(curl -sL https://www.privateinternetaccess.com/download/linux-vpn | grep https://installers.privateinternetaccess.com/download/pia-linux | head -n 1 | sed -r "s/(.*href=\")([^\"]*)(.*)/\2/")
piavpn_file=$(echo "${piavpn_url}" | awk -F / '{print $NF}')

curl --clobber -o "/home/${username}/Downloads/${piavpn_file}" -L "${piavpn_url}"
chown "${username}":"${username}" "/home/${username}/Downloads/${piavpn_file}"

