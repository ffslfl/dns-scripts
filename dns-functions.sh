#!/bin/sh

GetZoneFileSerial() {
	if [ -f "$1" ]; then
		INSOASpec="^\s*\S\+\s\+\([0-9]*\s\)\?\s*IN\s\+SOA\s\+"
		FirstSOALineAndFollowing="/""$INSOASpec""/,\$!d;"
		RemoveComments=":a;s/;.*$//g;"
		RemoveLineBreaks=":a;N;\$!ba;s/\n//g;"
		SearchPrintSerial="s/""$INSOASpec""\S\+\s\+\S\+\s\+\((\s\)\?\s*\([0-9]*\).*/\3/i"
		
		ZoneSerial=$(sed -e "$FirstSOALineAndFollowing""$RemoveComments""$RemoveLineBreaks""$SearchPrintSerial" "$1")
	fi
	echo "${ZoneSerial:-0}"
}
InsertZoneToIncludeFile() {
	if [ ! -f "$3" ]; then
		{
			echo "zone \"""$1""\" {"
			echo "	type master;"
			[ -n "$4" ] && echo "	dnssec-policy $4"";"
			echo "	file \"""$2""\";"
			echo "};"
		} > "$3"
	else
		[ -n "$4" ] && Extra="	dnssec-policy $4"";\n" || Extra=""
		
		sed -i "1i\
zone \"""$1""\" {\n\
	type master;\n""$Extra\
	file \"""$2""\";\n\
};" "$3"
	fi
}
GetAllSubNameservers() {
	Domain="$(echo "$1" | sed -e 's/\./\\\./g')"
	SubDomain="$(echo "$2" | sed -e 's/\./\\\./g')"
	sed -ne 's/^\s*'"$SubDomain"'\(\.'"$Domain"'\.\)\?\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Nn][Ss]\s\+\(\S\+\)/\3/p' "$3" | \
	sed -e 's/\([^.]\)$/\1\.'"$1"'\./g;s/\.$//g'
}
GetAllZoneNameservers() {
	Domain="""$(echo "$1" | sed -e 's/\./\\\./g')"
	sed -ne 's/^\s*\(@\|'"$Domain"'\.\)\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Nn][Ss]\s\+\(\S\+\)/\3/p' "$2" | \
	sed -e 's/\([^.]\)$/\1\.'"$1"'\./g;s/\.$//g'
}
GetReverseZoneFileFromZone() {
	echo "db.""$(echo "$1" | awk -F. '{ printf $(NF-2);for(i=NF-3;i>0;--i) printf "."$i}')"
}
FillIPv4MissingBlocks() {
	echo "$1" | sed -ne 's/^\([^.]\+\)\.\(\([^.]\+\)\.\)\?\(\([^.]\+\)\.\)\?\([^.]\+\)$/\1.\3.\5.\6/p' | sed -r 's/\.\./\.0\./g;s/\.\./\.0\./g'
}
GetReverseIPv4Domains() {
	IPFilled="$(FillIPv4MissingBlocks "${1%/*}")"
	Mask="${1##*/}"
	Statics=$((Mask / 8))
	Filler=$((Mask % 8))
	RevDomain="$(echo "$IPFilled" | awk -F. '{for(i='"$Statics"';i>0;--i)printf "."$i}')"".in-addr.arpa."
	if [ $Filler -eq 0 ]; then
		echo "${RevDomain#.}"
	else
		Filler=$((8 - Filler))
		Filler=$((1 << Filler))
		Start=$(echo "$IPFilled" | awk -F. '{printf $'"$((Statics+1))"'}')
		Start=$((Start - Start % Filler))
		for Sub in $(seq $Start $((Start + Filler - 1))); do
			echo "$Sub""$RevDomain"
		done
	fi
}
FillIPv6Zeroes() {
	echo "$1" | awk -F: 'BEGIN{OFS=""}{FillCount=9-NF; for(i=1;i<=NF;i++){if(length($i)!=0||i==1||i==NF) {$i=substr(("0000" $i), length($i)+1);} else {for(j=1;j<=FillCount;j++){$i=($i "0000");}}}; print}'
}
GetReverseIPv6Domains() {
	IPFilled="$(FillIPv6Zeroes "$(echo "${1%/*}" | awk '{print tolower($0)}')")"
	Mask="${1##*/}"
	Statics=$((Mask / 4))
	Filler=$((Mask % 4))
	RevDomain="$(echo "$IPFilled" | awk 'BEGIN{FS=""}{for(i='"$Statics"';i>0;i--) printf "." $i;}')"".ip6.arpa."
	if [ $Filler -eq 0 ]; then
		echo "${RevDomain#.}"
	else
		Filler=$((4 - Filler))
		Filler=$((1 << Filler))
		Start="$(printf %d 0x"$(echo "$IPFilled" | awk 'BEGIN{FS=""}{printf $'"$((Statics+1))"'}')")"
		Start=$((Start - Start % Filler))
		for Sub in $(seq $Start $((Start + Filler - 1))); do
			echo "$(printf %x "$Sub")""$RevDomain"
		done
	fi
}
GetReverseDomains() {
	Subnet="$1"
	if IsValidIPv4Subnet "$Subnet"; then
		GetReverseIPv4Domains "$Subnet"
	elif IsValidIPv6Subnet "$Subnet"; then
		GetReverseIPv6Domains "$Subnet"
	else
		TraceErrAndExit "$1"" is no valid Subnet"
	fi
}
ExpandHostname() {
	Hostname="$1"
	[ -n "${Hostname##*.}" ] && Hostname="$Hostname"".""$2"
	echo "$Hostname"
}
GetServernameSEDEntry() {
	CommunityName="$1"
	ServerName="$DNSSCRIPT_SERVER_NAME"
	if [ -z "${ServerName##*$CommunityName}" ]; then
		ServerName="\(""$ServerName"".\|""${ServerName%*.$CommunityName}""\)"
	else
		ServerName="\(""$ServerName"".\)"
	fi
	
	echo "$ServerName" | sed -r 's/\./\\\./g'
}
NormalizeZoneFileFormatting() {
	awk 'BEGIN{FS="\t"}{l=length($1);f=substr("                                    ", 1+length($1));
		s=substr("         ", 1+length($2));
		x=substr($0,length($1)+length($2)+3);
		print $1 f " " $2 s " " x}'
}
GetOwnGlueRecords() {
	ServerName="$DNSSCRIPT_SERVER_NAME"
	if [ -z "${ServerName##*$2}" ]; then
		ServerName="${ServerName%.$2}"
		sed -ne 's/^\s*'"$(GetServernameSEDEntry "$1")"'\s\+[Ii][Nn]\s\+\([Aa]\|[Aa]\{4\}\)\s\+\(.*\)$/'"$ServerName"'\tIN \2\t\3/p' "$3" | \
		NormalizeZoneFileFormatting
	fi
}
GetOwnHoods() {
	Entries="$(sed -ne "s/^\s*\(\S*\).*\s\+[Ii][Nn]\s\+[Nn][Ss]\s\+""$(GetServernameSEDEntry "$1")""\s*;\s*Subnets:\s*\([^;]*\)/\1 \3/p" "$2")"
	Entries="$(echo "$Entries" | sed -e '/^[eE][xX][tT][eE][rR][nN]\s/d' | sed -r 's/\s+/#/g')"	
	echo "$Entries"
}
IsValidIPv4Subnet() {
	[ -n "$(echo "$1" | sed -e '/[^/]*\/\([12]\?[0-9]\|3[0-2]\)$/!d')" ] && IsValidIPv4 "${1%/*}"
	return $?
}
IsValidIPv4() {
	[ -n "$(echo "$1" | sed -e '/^\(\(25[0-5]\|\(2[0-4]\|1[0-9]\|[1-9]\)\?[0-9]\)\.\)\{0,3\}\(25[0-5]\|\(2[0-4]\|1[0-9]\|[1-9]\)\?[0-9]\)$/!d')" ]
	return $?
}
IsValidIPv6Subnet() {
	[ -n "$(echo "$1" | sed -e '/[^/]*\/\([1-9]\?[0-9]\|1\([01][0-9]\|2[0-8]\)\)$/!d')" ] && IsValidIPv6 "${1%/*}"
	return $?
}
IsValidIPv6() {
	Max8BlocksMax4Hex="/^\([0-9a-fA-F]\{0,4\}[:]\{1,2\}\)\{1,7\}[0-9a-fA-F]\{0,4\}$/!d;"
	MaxOneDoubleColon="/^.*::.*::.*$/d;"
	SingleColon8BlocksOrNoSingleColonBeginEnd="/^\(\([^:]\+:\)\{7\}[^:]\+\|\(\|[^:].*\)::\(\|.*[^:]\)\)$/!d"
	[ -n "$(echo "$1" | sed -e "$Max8BlocksMax4Hex""$MaxOneDoubleColon""$SingleColon8BlocksOrNoSingleColonBeginEnd")" ]
	return $?
}
IPv4IsInSubnet() {
	IPFilled="$(FillIPv4MissingBlocks "$1")"
	SubnetIPFilled="$(FillIPv4MissingBlocks "${2%/*}")"
	Mask="${2##*/}"
	Statics=$((Mask / 8))
	BlockMask=$((Mask % 8))	
	IPStaticPart="$(echo "$IPFilled" | awk -F. '{for(i='"$Statics"';i>0;--i)printf "."$i}')"
	SubnetStaticPart="$(echo "$SubnetIPFilled" | awk -F. '{for(i='"$Statics"';i>0;--i) printf "."$i}')"
	AreEqual="$([ "$IPStaticPart" = "$SubnetStaticPart" ]; echo "$?")"
	if [ $AreEqual -eq 0 ] && [ $BlockMask -ne 0 ]; then
		BlockMask=$((8 - BlockMask))
		BlockMask=$((-1 << BlockMask))
		IPBlock=$(echo "$IPFilled" | awk -F. '{printf $'"$((Statics+1))"'}')
		SubnetBlock=$(echo "$SubnetIPFilled" | awk -F. '{printf $'"$((Statics+1))"'}')
		IPBlock=$((IPBlock & BlockMask))
		SubnetBlock=$((SubnetBlock & BlockMask))
		AreEqual="$([ $IPBlock -eq $SubnetBlock ]; echo "$?")"
	fi

	return $AreEqual
	
}
GetOwnKeysForZone () {
	DNSSECKeyFolder="$1"
	Domain="$2"
	if [ -n "$DNSSECKeyFolder" ];then
		for OwnKeyFile in "$DNSSECKeyFolder""K""$Domain"".+"*".key"; do
			sed -ne '/^;/d;s/^'"$Domain"'\.\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Dd][Nn][Ss][Kk][Ee][Yy]\s\+\(.*\)$/_dnsseckeys\.'"$Domain"'\.\tIN TXT\t\"\2\"/p' "$OwnKeyFile" | \
			NormalizeZoneFileFormatting
		done
	fi
}
UpdateDNSSECEntryCache () {
	Domain="$1"
	ZoneTempFolder="$2"
	CachedZoneFile="$3"
	DNSSECKeyFolder="$4"
	UpdateMaster=0
	
	Nameservers="$(GetAllZoneNameservers "$Domain" "$CachedZoneFile")"
	
	mkdir -p "$ZoneTempFolder"
	for KeyFile in "$ZoneTempFolder"*; do
		[ "$KeyFile" = "$ZoneTempFolder""*" ] || \
		mv "$KeyFile" "$ZoneTempFolder""Old""${KeyFile##*"$ZoneTempFolder"}"
	done
	for Nameserver in $Nameservers; do
		if [ "$Nameserver" = "$DNSSCRIPT_SERVER_NAME" ]; then
			DNSKEYS="$( GetOwnKeysForZone "$DNSSECKeyFolder" "$Domain" )"
		else
			DNSKEYS="$(delv @"$Nameserver" _dnsseckeys."$Domain" TXT 2>/dev/null | \
				sed -ne '/^;/d;s/^.*\sIN\s\+TXT\s\+"\(.*\)"$/'"$Domain"'.\tIN DNSKEY\t\1/p' | \
				NormalizeZoneFileFormatting )"
		fi
		if [ -n "$DNSKEYS" ] && [ "$DNSKEYS" != "$(cat "$ZoneTempFolder""OldKeys.""$Nameserver" 2>/dev/null)" ]; then
			echo "$DNSKEYS" > "$ZoneTempFolder""Keys.""$Nameserver"
			UpdateMaster=1
		elif [ -f "$ZoneTempFolder""OldKeys.""$Nameserver" ]; then
			mv "$ZoneTempFolder""OldKeys.""$Nameserver" "$ZoneTempFolder""Keys.""$Nameserver"
		fi
	done
	
	SEDDomain="$(echo "$Domain" | sed -e 's/\./\\\./g')"
	ChildServers="$( sed -ne '/^\s*\(@\|'"$SEDDomain"'\.\)\s/!s/^\s*\(\S\+\)\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Nn][Ss]\s\+\(\S\+\);\?.*$/\1#\3/p' "$CachedZoneFile" | \
		sed -e 's/\([^.]\)$/\1\.'"$Domain"'\./g;s/\.$//g;s/\([^.]\)#/\1\.'"$Domain"'\.#/g;s/\.#/#/g' )"
	for ChildServer in $ChildServers; do
		DNSKEYS="$(delv @"${ChildServer##*\#}" "${ChildServer%%\#*}" CDS 2>/dev/null | \
			sed -ne '/^;/d;s/^.*\sIN\s\+CDS\s\+\(.*\)$/'"${ChildServer%%\#*}"'.\tIN DS\t\1/p' | \
			NormalizeZoneFileFormatting )"
		
		if [ -n "$DNSKEYS" ]; then
			DNSKEYS="$(echo "$DNSKEYS" | sed -e '/\sIN\s\+DS\s\+0\s\+0\s\+0\s\+0/d')"
			if [ "$DNSKEYS" != "$(cat "$ZoneTempFolder""OldChildKeys.""$ChildServer" 2>/dev/null)" ]; then
				[ -z "$DNSKEYS" ] || echo "$DNSKEYS" > "$ZoneTempFolder""ChildKeys.""$ChildServer"
				UpdateMaster=1
			elif [ -n "$DNSKEYS" ]; then
				mv "$ZoneTempFolder""OldChildKeys.""$ChildServer" "$ZoneTempFolder""ChildKeys.""$ChildServer"
			elif [ -f "$ZoneTempFolder""OldKeys.""$Nameserver" ]; then
				UpdateMaster=1
			fi
		elif [ -f "$ZoneTempFolder""OldChildKeys.""$Nameserver" ]; then
			mv "$ZoneTempFolder""OldChildKeys.""$ChildServer" "$ZoneTempFolder""ChildKeys.""$ChildServer"
		fi
	done
	
	for KeyFile in "$ZoneTempFolder""Old"*; do
		[ "$KeyFile" = "$ZoneTempFolder""Old*" ] || \
		rm -f "$KeyFile"
	done
	echo "$UpdateMaster"
}
ReloadZone() {
	if [ $((DNSSCRIPT_BIND_RELOAD_VER)) -eq 0 ]; then
		systemctl reload bind9
	elif [ $((DNSSCRIPT_BIND_RELOAD_VER)) -eq 1 ]; then
		for Zone in $2; do
			rndc reload "$1" IN "$Zone" || touch "/tmp/dnsscript-forcereconf"
		done
	elif [ $((DNSSCRIPT_BIND_RELOAD_VER)) -eq 2 ]; then
		/etc/init.d/named reload
	fi
}

TraceErrAndExit() {
	echo "$1" 1>&2
	exit 1
}

