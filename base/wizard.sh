#!/bin/bash

set -uf -o pipefail

# define functions
calculate_swap () {
	mem_calculated=$(free --giga | grep Mem: | awk '{print $2}')
	mem_calculated=$(( (mem_calculated + 1) & ~1 ))
	case $((
	(mem_calculated >= 0 && mem_calculated <= 2)    * 1 +
	(mem_calculated >  2 && mem_calculated <= 8)    * 2 +
	(mem_calculated >  8 && mem_calculated <= 64)   * 3 +
	(mem_calculated >  64)				* 4)) in
	(1) swap_size=$(awk "BEGIN {print ($mem_calculated)*3}")
	;;
	(2) swap_size=$(awk "BEGIN {print ($mem_calculated)*2}")
	;;
	(3) swap_size=$(awk "BEGIN {print ($mem_calculated)*1.5}")
	;;
	(4) swap_size="noswap"
	;;
	esac
}

valid_device() {
	grep -P "/dev/(sd|nvme|vd)" | grep -vF "iso9660";
}

drive_table() {
	mapfile -t device_names < <(lsblk -dpn -o NAME,FSTYPE | valid_device | awk '{print $1}'; )
	device_table=$(lsblk -dpn -o NAME,MODEL,SIZE,FSTYPE | valid_device | awk -F '\t' '{printf "%s %-10s %s\n", $1, $2, $3}')
	readarray -t device_table < <(echo "$device_table")
}

dialog_error() {
	dialog  \
		--clear \
		--title "Error" \
		--msgbox "$1" 0 0
}

dialog_root_device() {
	local device_menu command message
	device_menu=()
		for i in "${!device_table[@]}"; do
		device_menu+=("$(( i + 1 ))" "${device_table[$i]}")
	done

	message="An EFI partition will be created on the root device "
	message+="and the remaining space will be used for the BTRFS partition.\n"
 	message+="All data on the root device will be destroyed during installation."

	command=(dialog --stdout \
		--clear \
		--title "Select root device" \
		--menu "$message" 0 0 0)
	selected_device=$("${command[@]}" "${device_menu[@]}")
	if ! command; then exit ; fi

	root_device="${device_names[$(( selected_device - 1 ))]}"
}

dialog_hostname() {
	local command

	command=(dialog --stdout \
		--clear \
		--title "Machine" \
		--inputbox "Enter hostname:" 0 0 "")
	hostname=$("${command[@]}")
	if ! command; then exit ; fi

	if [ -z "$hostname" ]; then
	dialog_error "Hostname can't be empty."
	dialog_hostname
	return 0
	fi
}

get_video_cards() {
	video_card_list="$( lspci -v -m | grep VGA -A 7 | grep -w Vendor | tr "[:upper:]" "[:lower:]" )"
	for line in $video_card_list; do
		case $line in
	*intel*)
		gpu_vendor+=( "intel" )
		;;
	*nvidia*)
		gpu_vendor+=( "nvidia" )
		;;
	*advanced\ micro\ devices*|*ati*|*amd*)
		gpu_vendor+=( "amd" )
		;;
	*hat,*)
		gpu_vendor+=( "virtual" )
		;;
		esac
	done
	video_card_manufacturers=(); while IFS= read -r -d '' x; do video_card_manufacturers+=("$x"); done < <(printf "%s\0" "${gpu_vendor[@]}" | sort -uz)

}

get_resolution() {
	monitor_max="$(hwinfo --monitor | grep "Max. Resolution: " | awk '{ print $3 }')"
	case $monitor_max in
		3840x2160)
		max_resolution="4k" ;;
		2560x1440)
		max_resolution="2k" ;;
		1920x1080)
		max_resolution="1080p" ;;
		*)
		max_resolution="1080p" ;;
	esac
}

get_microcode() {
cpu_vendor=$(grep -F "vendor_id" /proc/cpuinfo)
echo "$cpu_vendor" | grep -qF "AuthenticAMD" && microcode="amd-ucode" || microcode="intel-ucode"
}

get_motherboard() {
	motherboard_lookup="$(dmidecode -t 2 | grep -w Manufacturer | tr "[:upper:]" "[:lower:]")" || true
	case "$motherboard_lookup" in
		*asus*)
		motherboard_manufacturer="asus" ;;
		*)
		motherboard_manufacturer="generic" ;;
	esac
}

dialog_confirm() {
	local i fields message width

	width=40

	i=0
	fields=()
	fields+=("Hostname:	" "$(( ++i ))"	1	"$hostname"				"$i"	22	"$width" 0 2)
	fields+=("Microcode:	" "$(( ++i ))"	1	"$microcode"				"$i"	22	"$width" 0 2)
	fields+=("Root Device:	" "$(( ++i ))"	1	"${root_device}"			"$i"	22	"$width" 0 2)
	fields+=("Swap (GB):	" "$(( ++i ))"	1	"$swap_size"				"$i"	22	"$width" 0 2)
	fields+=("Video Cards:	" "$(( ++i ))"	1	"${video_card_manufacturers[*]}"	"$i"	22	"$width" 0 2)
	fields+=("Motherboard:	" "$(( ++i ))"	1	"$motherboard_manufacturer"		"$i"	22	"$width" 0 2)
	fields+=("Resolution:	" "$(( ++i ))"	1	"$max_resolution"			"$i"	22	"$width" 0 2)


	message="Please review installation options.\n"
	message+="The selected devices will be formatted right away."

	dialog \
	--clear \
	--title "Confirmation" \
	--mixedform "$message" 0 0 0 \
	"${fields[@]}" 2> /dev/null
}


calculate_swap
drive_table
dialog_root_device
dialog_hostname
get_video_cards
get_microcode
get_motherboard
get_resolution

dialog_confirm
