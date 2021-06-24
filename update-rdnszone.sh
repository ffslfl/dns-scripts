#!/bin/sh

. ./dns-functions.sh

ReverseDomain="$1"
ReverseZone="${ReverseDomain%*.}"
ForwardZones="$2"
ReverseZoneFile="$3"
TempDir="/tmp/""$ReverseZone"
TTL="${4%% *}"
ReReExMi="${4#* }"
View="$5"

GetIPEntries() {
	if [ -z "$RZoneIsIPv6" ]; then
		IPPattern="[aA]\s\+\([0-9\.]\+\)"
	else
		IPPattern="[aA]\{4\}\s\+\([0-9a-f:]\+\)"
	fi
	
	sed -ne "s/^\s*\(\S\+\)\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+""$IPPattern"".*/\1\/\3/p" "$1"
}

ReverseEntry() {
	if [ -z "$RZoneIsIPv6" ]; then
		GetReverseDomains "$1""/32"
	else
		GetReverseDomains "$1""/128"
	fi
}

if [ -z "${ReverseDomain##*.in-addr.arpa.}" ]; then
	RZoneIsIPv6=""
elif [ -z "${ReverseDomain##*.ip6.arpa.}" ]; then
	RZoneIsIPv6=1
else
	TraceErrAndExit "$ReverseDomain"" is no valid reverse domain"
fi

mkdir -p "$TempDir"

for ForwardZone in $ForwardZones; do
	ZoneFile="${ForwardZone#*/}"
	Serial="$(GetZoneFileSerial "$ZoneFile")"
	NewReverseSerial=$((Serial + NewReverseSerial))
done

OldSerial="$(GetZoneFileSerial "$ReverseZoneFile")"

if [ $((NewReverseSerial)) -gt $((OldSerial)) ]; then
	{
		echo "$ReverseDomain $TTL IN SOA $DNSSCRIPT_SERVER_NAME""."" $DNSSCRIPT_CONTACT_EMAIL $NewReverseSerial $ReReExMi"
		echo "$ReverseDomain $TTL IN NS $DNSSCRIPT_SERVER_NAME""."""
		Static="/""$ReverseZoneFile"
		Static="${Static%/*}""/static.""${Static##*/}"
		Static="${Static#*/}"
		[ -f "$Static" ] && echo "$(cat "$Static")"
		echo
	} > "$TempDir/$ReverseZone"
	
	for ForwardZone in $ForwardZones; do
		ZoneName="${ForwardZone%%/*}"
		ZoneFile="${ForwardZone#*/}"
		ZoneRevNSSubnets="$(sed -ne 's/^\s*\S\+\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Nn][Ss]\s\+\(\S\+\).*;\s*Subnets:\s*\([^;]*\)\s*\(;[^;]*\s*\)$/\2@\3/p' "$ZoneFile" |
			sed -e 's/\(.*[^\.]\)@/\1\.'"$ZoneName"'\.@/;s/@/ /;s/\s\+/@/g')"
		for NSSubnets in $ZoneRevNSSubnets; do
			Subnets="$(echo "${NSSubnets#*@}" | sed -e 's/@/ /g')"
			for Subnet in $Subnets; do
				for ReverseNS in $(GetReverseDomains "$Subnet"); do
					if [ -n "$ReverseNS" ] && [ -z "${ReverseNS##*$ReverseDomain}" ]; then
						echo "$ReverseNS $TTL IN NS ${NSSubnets%%@*}" >> "$TempDir/$ReverseZone"
					fi
				done
			done
		done
		
		IPEntries="$(GetIPEntries "$ZoneFile")"
		
		for IPEntry in $IPEntries; do
			IP="${IPEntry#*/}"
			IP="$(ReverseEntry "$IP")"
			if [ -z "${IP##*$ReverseDomain}" ]; then
				Host="$(ExpandHostname "${IPEntry%%/*}" "$ZoneName"".")"
				echo "$IP $TTL IN PTR $Host" >> "$TempDir/$ReverseZone"
			fi
		done
	done
	
	named-checkzone -o "$ReverseZoneFile" "$ReverseDomain" "$TempDir/$ReverseZone" >/dev/null
	ReloadZone "$ReverseDomain" "$View"
fi

rm -r "$TempDir"

