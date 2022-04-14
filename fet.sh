#!/bin/sh
#
#    fet.sh
#
# modified by k1f0
# -> no intention of supporting non-Linux OS's
# -> changes are mostly personal preference

# supress errors
exec 2>/dev/null
set --
eq() {  # equals  |  [ a = b ] with globbing
	case $1 in
		$2) ;;
		*) return 1;;
	esac
}

## Distro
# freedesktop.org/software/systemd/man/os-release.html
# a common file that has variables about the distro
for os in /etc/os-release /usr/lib/os-release; do
	# some POSIX shells exit when trying to source a file that doesn't exist
	[ -f $os ] && . $os && break
done

if [ -e /proc/$$/comm ]; then
	## Terminal
	while [ ! "$term" ]; do
		# loop over lines in /proc/pid/status until it reaches PPid
		# then save that to a variable and exit the file
		while read -r line; do
			eq "$line" 'PPid*' && ppid=${line##*:?} && break
		done < "/proc/${ppid:-$PPID}/status"

		# Make sure not to do an infinite loop
		[ "$pppid" = "$ppid" ] && break
		pppid=$ppid

		# get name of binary
		read -r name < "/proc/$ppid/comm"

		case $name in
			*sh|"${0##*/}") ;;  # skip shells
			*[Ll]ogin*|*init*|*systemd*) break;;  # exit when the top is reached
			# anything else can be assumed to be the terminal
			# this has the side affect of catching tmux, but tmux
			# detaches from the terminal and therefore ignoring that
			# will just make the init the term
			*) term=$name
		esac
	done

	## WM/DE
    [ "$wm" ] ||
        # use xprop to determine WM
		winID=$(xprop -root -notype | grep "_NET_SUPPORTING_WM_CHECK: window" |
		cut -d "#" -f 2 | tr -d '[:blank:]')
		attr=$(xprop -id "${winID}" -notype -f _NET_WM_NAME 8t)
		wm=$(echo "${attr}" | grep "_NET_WM_NAME = " |
		tr -d '"[:blank:]' | cut -d '=' -f 2)

	## Memory
	# loop over lines in /proc/meminfo until it reaches MemTotal,
	# then convert the amount (second word) from KB to MB
	while read -r line; do
		eq "$line" 'MemTotal*' && set -- $line && break
	done < /proc/meminfo
	mem="$(( $2 / 1000 ))MB"

	## Processor
	while read -r line; do
		case $line in
			vendor_id*) vendor="${line##*: } ";;
			model\ name*) cpu=${line##*: }; break;;
		esac
	done < /proc/cpuinfo

	## Uptime
	# the simple math is shamefully stolen from aosync
	IFS=. read -r uptime _ < /proc/uptime
	d=$((uptime / 60 / 60 / 24))
	up=$(printf %02d:%02d $((uptime / 60 / 60 % 24)) $((uptime / 60 % 60)))
	[ "$d" -gt 0 ] && up="${d}d $up"

	## Kernel
	read -r _ _ version _ < /proc/version
	kernel=${version}
	eq "$version" '*Microsoft*' && ID="fake $ID"

	## Motherboard // laptop
	read -r model < /sys/devices/virtual/dmi/id/product_name
	# invalid model handling
	case $model in
		# alternate file with slightly different info
		# on my laptop it has the device model (instead of 'hp notebook')
		# on my desktop it has the extended motherboard model
		'System '*|'Default '*)
			read -r model < /sys/devices/virtual/dmi/id/board_name
	esac

	## Packages
	# clean environment, then make every file in the dir an argument,
	# then save the argument count to $pkgs
	set --
	# kiss, arch, debian, void, gentoo
	for i in '/var/db/kiss/installed/*'  '/var/lib/pacman/local/[0-9a-z]*' \
	'/var/lib/dpkg/info/*.list'  '/var/db/xbps/.*'  '/var/db/pkg/*/*'; do
		set -- $i
		[ $# -gt 1 ] && pkgs=$# && break
	done

	read -r host < /proc/sys/kernel/hostname
fi

# GPU
# This is probably very inefficient and could be done better 
# but here we go
gpu=$(glxinfo | grep 'Device' | cut -d ':' -f 2 | cut -d '(' -f 1 | cut -c 2-)

# Shorten $cpu and $vendor
# this is so messy due to so many inconsistencies in the model names
vendor=${vendor##*Authentic}
vendor=${vendor##*Genuine}
cpu=${cpu##*) }
cpu=${cpu%% @*}
cpu=${cpu%% CPU}
cpu=${cpu##CPU }
cpu=${cpu##*AMD }
cpu=${cpu%% with*}
cpu=${cpu% *-Core*}

# print first line with user@hostname
printUserHost() {
	seperator="─"
	printf "\e[1m\e[9%sm%s\e[0m\e[1m@\e[9%sm%s\e[0m\n" "$accentNumber" "$1" "$accentNumber" "$2"
	userHost="$1@$2"
	for ((i = 0; i < ${#userHost}; i++)); do
		seperatorLine+="$seperator"
	done
	printf "%s\t\n" "$seperatorLine"
}

# print the other normal fetch lines
printNormal() {
	printf "\e[1m\e[9%sm%s\e[0m\t%s\n" "$accentNumber" "$1" "$2"
}

# default values
info="space userHost os kernel wm cpu gpu terminal space"
# accent color number (try 0-9)
accentNumber=7

for i in $info; do
	case $i in
		userHost) printUserHost "$USER" "$host";;
		os) printNormal os "$NAME";;
		kernel) printNormal kernel "$kernel";;
		wm) printNormal wm "${wm}";;
		shell) printNormal shell "${SHELL}";;
		cpu) printNormal cpu "$vendor$cpu";;
		gpu) printNormal gpu "$gpu";;
		ram) printNormal mem "$mem";;
		up) printNormal up "$up";;
		host) printNormal host "$model";;
		packages) printNormal pkgs "$pkgs";;
		terminal) printNormal term "$term";;
		space) echo;;
	esac
done
