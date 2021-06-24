#!/bin/sh

. ./dns-functions.sh

InternalZoneFile="$1"
ExternalZoneFile="$2"
ExternalZone="$3"
ExternalView="$4"
CommunityExternal="$5"
InternalViews="$6"

SerialIntern="$(GetZoneFileSerial "$InternalZoneFile")"
SerialExtern="$(GetZoneFileSerial "$ExternalZoneFile")"

if [ $((SerialIntern)) -gt $((SerialExtern)) ]; then
	ZoneContent="$(sed -e '/^[^;]*\s\(10.\|[fF][cdCD][0-9a-fA-F]\{2\}:\)\S*\s*\(;.*\)\?$/d; \
	s/^[^;^@]*\s\+\([^;]*\)\s[Ii][Nn]\s\+[Ss][Oo][Aa]\s/@                         \1 IN SOA /g' "$InternalZoneFile")"
	
	[ -n "$( echo "$ZoneContent" | sed -e '/^[eE][xX][tT][eE][rR][nN]\s[^;]*\s[Ii][Nn]\s\+[Nn][Ss]/!d')" ] \
		&& ZoneContent="$(echo "$ZoneContent" | sed -e '/^@\s[^;]*\s[Ii][Nn]\s\+[Nn][Ss]\s/d; \
			s/^[eE][xX][tT][eE][rR][nN]\s\([^;]*\s[Ii][Nn]\s\+[Nn][Ss]\s.*\)/@      \1/g; \
			s/^\(@                         [^;]* IN SOA\)\s\+\S\+\s\+\S\+\s/\1 '"$DNSSCRIPT_SERVER_NAME"'. '"$DNSSCRIPT_CONTACT_EMAIL"' /g')"
	echo "$ZoneContent" > "$ExternalZoneFile"
	ReloadZone "$ExternalZone" "$ExternalView"
	[ -z "$CommunityExternal" ] || ReloadZone "$CommunityExternal" "$InternalViews"
fi

