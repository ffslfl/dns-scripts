#!/bin/sh

. ./dns-functions.sh

IncludeFile="$1"
RemoteLocation="$2"
Tables="$3"

rm -f "$IncludeFile"

if [ -z "$Tables" ]; then
	# this is only a rude fallback and not recommended
	# create your own file on a gateway with the community routing tables and use this one
	RemoteFile="$(curl -s -S -f "https://gw01.herpf.fff.community/ffdns/icvpn-acl.conf")"
	if [ -n "$RemoteFile" ]; then
		echo "$RemoteFile" > "$IncludeFile"
	fi
else
	Installed4Routes=""
	Installed6Routes=""
	for Table in $Tables; do
		Installed4Routes="$(echo "$Installed4Routes" && ip -4 ro sh ta "$Table")"
		Installed6Routes="$(echo "$Installed6Routes" && ip -6 ro sh ta "$Table")"
	done
	PublicSubs="$(echo "$Installed6Routes" | \
		sed -e '/^default from/!d;s/.* from \(\S\+\).*/\1/g')"
	Privatev4Prefix="\(192\.168\.\|172\.\(1[6-9]\|2[0-9]\|3[01]\)\.\|10\.\)"
	Privatev6Prefix="\([fF][cCdD][0-9a-fA-F]\{2\}:\)"
	Publicv4Singles="$(echo "$Installed4Routes" | \
		sed -e 's/^\(\S\+\)\s.*/\t\1;/g;/^\t'"$Privatev4Prefix"'\|^\t\(unreachable\|default\|0\.\)\|^$/d')"
	Publicv6Singles="$(echo "$Installed6Routes" | \
		sed -e 's/^\(\S\+\)\s.*/\1/g;/^'"$Privatev6Prefix"'\|^\(unreachable\|default\|::\|64:ff9b::\)\|^$/d')"
	
	# the following code is not well optimized yet and may take a bit to process
	# therefore it is not recommended to activate it on hardware-routers
	# even in other environments it did not speed up bind9 measurable, its just for a smaller acl-file, e.g. for redistribution

	#for Subnet in $PublicSubs; do
	#	SubnetIPFilled="$(FillIPv6Zeroes "$(echo "${Subnet%/*}" | awk '{print tolower($0)}')")"
	#	Mask="${Subnet##*/}"
	#	Statics=$((Mask / 4))
	#	BlockMask=$((Mask % 4))
	#	if [ $BlockMask -ne 0 ]; then
	#		BlockMask=$((4 - BlockMask))
	#		BlockMask=$((-1 << $BlockMask))
	#		SubnetBlock="$(printf %d 0x"$(echo "$SubnetIPFilled" | awk 'BEGIN{FS=""}{printf $'"$((Statics+1))"'}')")"
	#		SubnetBlock=$((SubnetBlock & BlockMask))
	#	fi
	#	
	#	SubnetStaticPart="$(echo "$SubnetIPFilled" | awk 'BEGIN{FS=""}{for(i='"$Statics"';i>0;i--) printf $i;}')"
	#	
	#	for Single in $Publicv6Singles; do
	#		IPFilled="$(FillIPv6Zeroes "$(echo "${Single%/*}" | awk '{print tolower($0)}')")"
	#		MaskIP="$( echo "$Single" | sed -e 's/^[^/]*\(\/\)\?//g')"
	#		MaskIP="${MaskIP:-128}"
	#		IsInSub="$([ $((Mask)) -le $((MaskIP)) ]; echo "$?")"
	#		if [ $IsInSub -eq 0 ]; then
	#			IPStaticPart="$(echo "$IPFilled" | awk 'BEGIN{FS=""}{for(i='"$Statics"';i>0;i--) printf $i;}')"
	#			IsInSub="$([ "$IPStaticPart" = "$SubnetStaticPart" ]; echo "$?")"
	#		fi
	#		if [ $IsInSub -eq 0 ] && [ $BlockMask -ne 0 ]; then
	#			IPBlock="$(printf %d 0x"$(echo "$IPFilled" | awk 'BEGIN{FS=""}{printf $'"$((Statics+1))"'}')")"
	#			IPBlock=$((IPBlock & BlockMask))
	#			IsInSub="$([ $IPBlock -eq $SubnetBlock ]; echo "$?")"
	#		fi
	#		
	#		! [ $IsInSub -eq 0 ] \
	#			&& NewSingles="$( [ -n "$NewSingles" ] && echo "$NewSingles"; echo "$Single")"
	#	done
	#	Publicv6Singles="$NewSingles"
	#	NewSingles=""
	#done	
	
	{
		echo "acl icvpnrange {" 
		echo "	icvpnlocal;"
		echo "$PublicSubs" | sed -e 's/\(.*\)/\t\1;/g'
		echo "$(curl -s -S -f "$RemoteLocation""external.dnsserverips" | sed -e 's/^/\t/g;s/$/;/g')"
		echo "$Publicv4Singles"
		echo "$Publicv6Singles" | sed -e 's/\(.*\)/\t\1;/g'
		echo "};"
	} > "$IncludeFile"
fi

