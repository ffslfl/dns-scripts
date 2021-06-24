#!/bin/sh

. ./dns-functions.sh

HoodZoneFile="$1"
Domain="$2"
Subnets="$3"
View="$4"


DomainReg=".""$Domain"
DomainReg="$(echo "$DomainReg" | sed -e 's/\./\\\./g')"

GetLeaseEntriesInSubnet() {
	echo "$1" | while read -r LeaseLine; do
		if IPv4IsInSubnet "${LeaseLine##*	}" "$2";then
			echo "$LeaseLine"
		fi
	done
}

OldLeases="$(sed -e '/^;### Leases ###/,$!d' "$HoodZoneFile" | sed 1d)"

if [ -f "/tmp/dhcp.leases" ]; then
	DnsmasqLeases="$(sed -ne 's/^\s*\(\S\+\s\+\)\{2\}\(\S\+\)\s\+\([_0-9a-zA-Z-]\+\)\s\+.*/\3	IN A	\2/p' "/tmp/dhcp.leases")"
	for Subnet in $Subnets; do
		IsValidIPv4Subnet "$Subnet" && NewLeases="$(echo "$NewLeases"; GetLeaseEntriesInSubnet "$DnsmasqLeases" "$Subnet")"
	done
fi

for Leasefile in /tmp/hosts/*; do
	if [ -n "${Leasefile##*/tmp/hosts/\*}" ]; then
		NewLeases="$(echo "$NewLeases"; sed -ne 's/^\s*\([0-9.]*\)\s\+\([_0-9a-zA-Z-]\+\)'"$DomainReg"'.*/\2	IN A	\1/p' "$Leasefile")"
		NewLeases="$(echo "$NewLeases"; sed -ne 's/^\s*\([0-9a-fA-F:]*\)\s\+\([_0-9a-zA-Z-]\+\)'"$DomainReg"'.*/\2	IN AAAA	\1/p' "$Leasefile")"
	fi
done

NewLeases="$(echo "$NewLeases" |
			sed -ne 's/^\(\(\(\S\+\)'"$DomainReg"'\)\|\(\S\+\)\)\(.*\)$/\3\4\5/p' |
			awk '!a[$0]++' |
# uncomment and duplicate to secure static DNS-Entries
#			sed -e '/^dns\s\+.*/d' |
			NormalizeZoneFileFormatting)"
if [ "$NewLeases" != "$OldLeases" ]; then
	NewSerial="$(GetZoneFileSerial "$HoodZoneFile")"
	NewSerial=$((NewSerial+1))
	sed -i -e 's/^\(\s*\)\(\S\+\)\(\s*;\s*Serial.*\)/\1'"$NewSerial"'\3/g' "$HoodZoneFile"
	sed -i -e '/^;### Leases ###/,$d' "$HoodZoneFile"
	{
		echo ";### Leases ###"
		echo "$NewLeases"
	} >> "$HoodZoneFile"
	ReloadZone "$Domain" "$View"
fi

