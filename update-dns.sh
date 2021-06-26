#!/bin/sh

# exit script when command fails
set -e

# Communityconfig
CommunityDomain="ffslfl.community"
CommunityExternPrefix="extern"
CommunitySubnets="10.24.32.0/19 fd07:96ae:572e::/48"
RemoteLocation="https://raw.githubusercontent.com/ffslfl/dns/main/"
DNSSECPolicy=""

# Serverconfig
export DNSSCRIPT_CONTACT_EMAIL=info.schleswig-flensburg.frefiunk.net.
# DNSSCRIPT_SERVER_NAME must be the server given in community zone files NS entry (Full Hostname, w/o trailing dot)
export DNSSCRIPT_SERVER_NAME=dnsprim.ffslfl.community
UpdateScriptsFolder="/usr/lib/ffslfldns/"
ZoneFilesFolder="/etc/bind/ffslfl/"
BindIncludeFileFolder="/etc/bind/"
DNSSECKeyFolder="/etc/bind/keys/"
TempFolder="/tmp/dnsscripts/"
# specify the bird/babel or other routing table[s]
# if RoutingTables is empty, the ICVPN-ACL-List will be fetched remotely (for servers that are no gateway)
#RoutingTables="10"
RoutingTables=""

# -1 -> disable bind [restart|reload]
# 0 -> Debian (and like) systemctl [reload|restart] bind9
# 1 -> use rndc to [reload zone|reconfig] (recommended; rndc needs setup first)
# 2 -> OpenWRT /etc/init.d/named [reload|restart]
export DNSSCRIPT_BIND_RELOAD_VER=0

InternalViews="icvpn-internal-view icvpn-internal-dns64-view"
ExternalView="external-view"

# TTL Refresh Retry Expire Minimum
TTLReReExMi="3600 2000 6400 2419200 86400"

# ForwardZones: "<Zone>/<Zonendatei>" ; optionaly multiple " ""<ZoneX>/<ZonendateiX>" no spaces in full filename
ForwardZones="$CommunityDomain""/""$ZoneFilesFolder""db.icvpn-internal-view.""$CommunityDomain"


#############################################################
cd "$UpdateScriptsFolder"

. ./dns-functions.sh

FirstInternal="$( echo "$InternalViews" | sed -ne 's/^\(\S\+\)\s.*$/\1/p')"
BindIcvpnAclTmp="$TempFolder""icvpn-acl.conf"
BindIcvpnAcl="$BindIncludeFileFolder""icvpn-acl.conf"
[ -z "$CommunityExternPrefix" ] || CommunityExternDomain="$CommunityExternPrefix"".""$CommunityDomain"

mkdir -p "$TempFolder""cache"

for IView in $InternalViews; do
	rm -f "$TempFolder""$IView"".conf"
done
rm -f "$TempFolder""$ExternalView"".conf"

CachedMasterFile="$TempFolder""cache/db.""$CommunityDomain"
PreFetchMasterSerial="$(GetZoneFileSerial "$CachedMasterFile")"
curl -s -S -f "$RemoteLocation""db.""$CommunityDomain" --output "$CachedMasterFile"
PostFetchMasterSerial="$(GetZoneFileSerial "$CachedMasterFile")"
ServeMasterZone="$( GetAllZoneNameservers "$CommunityDomain" "$CachedMasterFile" | awk '{for(i=NF;i>0;--i) if($i=="'"$DNSSCRIPT_SERVER_NAME"'") {printf 1}}')"
if [ -n "$CommunityExternDomain" ]; then
	if [ -n "$ServeMasterZone" ]; then
		ServeExtZone="1"
	else
		ServeExtZone="$( GetAllSubNameservers "$CommunityDomain" "$CommunityExternPrefix" "$CachedMasterFile" | awk '{for(i=NF;i>0;--i) if($i=="'"$DNSSCRIPT_SERVER_NAME"'") {printf 1}}')"
	fi
else
	ServeExtZone=""
fi

if [ -n "$ServeMasterZone" ] || [ -n "$ServeExtZone" ]; then
	sed -i -e '/^\s*_dnsseckeys\./d' "$CachedMasterFile"
	FileForExternGeneration="$CachedMasterFile"
	if [ -n "$ExternalView" ]; then
		ExternFile="$ZoneFilesFolder""db.""$ExternalView"".""$CommunityDomain"
	else
		ExternFile="$ZoneFilesFolder""db.""$CommunityExternDomain"
	fi
	LocalMasterSerial=$((PostFetchMasterSerial))
	if [ -n "$ServeMasterZone" ]; then
		MasterFile="$ZoneFilesFolder""db.""$FirstInternal"".""$CommunityDomain"
		FileForExternGeneration="$MasterFile"
		UpdateMaster=0
		ZoneTempFolder="$TempFolder""cache/""$CommunityDomain""/"
	
		UpdateMaster="$(UpdateDNSSECEntryCache "$CommunityDomain" "$ZoneTempFolder" "$CachedMasterFile"  "$DNSSECKeyFolder")"
		[ $((PostFetchMasterSerial)) -le $((PreFetchMasterSerial)) ] || UpdateMaster=1
		
		if [ $UpdateMaster -ne 0 ]; then
			cp -f "$CachedMasterFile" "$CachedMasterFile""I"
			for KeyFile in "$ZoneTempFolder"*; do
				[ "$KeyFile" = "$ZoneTempFolder""*" ] || \
				cat "$KeyFile" >> "$CachedMasterFile""I"
			done
			LocalMasterSerial="$(GetZoneFileSerial "$MasterFile")"
			
			if [ $((PostFetchMasterSerial)) -le $((LocalMasterSerial)) ]; then
				LocalMasterSerial=$((LocalMasterSerial+1))
				sed -i -e 's/^\(\s*\)'"$PostFetchMasterSerial"'\(\s*;\s*[Ss]erial.*\)$/\1'"$LocalMasterSerial"'\3/g' "$CachedMasterFile""I"
				sed -i -e 's/^\(\s*\S\+\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Ss][Oo][Aa]\s\+\S\+\s\+\S\+\s\+\)'"$PostFetchMasterSerial"'\(\s\+.*\)$/\1'"$LocalMasterSerial"'\3/g' "$CachedMasterFile""I"
			else
				LocalMasterSerial=$((PostFetchMasterSerial))
			fi
			mv "$CachedMasterFile""I" "$MasterFile"
			ReloadZone "$CommunityDomain" "$InternalViews"
			
			for IView in $InternalViews; do
				InternViewMasterZone="$ZoneFilesFolder""db.""$IView"".""$CommunityDomain"
				[ -f "$InternViewMasterZone" ] || ln -s "$MasterFile" "$InternViewMasterZone"
				InsertZoneToIncludeFile "$CommunityDomain" "$InternViewMasterZone" "$TempFolder""$IView"".conf" "$DNSSECPolicy"
			done
		fi
	for Subnet in $CommunitySubnets; do
		ReverseDomains="$(GetReverseDomains "$Subnet")"
		for RDomain in $ReverseDomains; do
			ReverseZoneFile="$(GetReverseZoneFileFromZone "${RDomain%*.}")"
			! curl -s -f "$RemoteLocation""static.""$ReverseZoneFile" \
				--output "$ZoneFilesFolder""static.""$ReverseZoneFile" && \
				rm -f "$ZoneFilesFolder""static.""$ReverseZoneFile"
			./update-rdnszone.sh "$RDomain" "$ForwardZones" "$ZoneFilesFolder""$ReverseZoneFile" "$TTLReReExMi" "$InternalViews"
			for IView in $InternalViews; do
					InsertZoneToIncludeFile "${RDomain%*.}" "$ZoneFilesFolder""$ReverseZoneFile" "$TempFolder""$IView"".conf"
			done
		done
	done
		if [ -n "$ExternalView" ]; then
			InsertZoneToIncludeFile "$CommunityDomain" "$ExternFile" "$TempFolder""$ExternalView"".conf" "$DNSSECPolicy"
		fi
	fi
	
	UpdateExternView=0
	if [ -n "$ExternalView" ] || [ -n "$ServeExtZone" ]; then
		SerialExtern="$(GetZoneFileSerial "$ExternFile")"
		if [ $((LocalMasterSerial)) -gt $((SerialExtern)) ]; then
			sed -e '/^[^;]*\s\(10.\|[fF][cdCD][0-9a-fA-F]\{2\}:\)\S*\s*\(;.*\)\?$/d; \
			s/^[^;^@]*\s\+\([^;]*\)\s[Ii][Nn]\s\+[Ss][Oo][Aa]\s/@                         \1 IN SOA /g' "$FileForExternGeneration" \
			> "$ExternFile"
			UpdateExternView=1
			[ -z "$ExternalView" ] || ReloadZone "$CommunityExternDomain" "$ExternalView"
		fi
	fi
	
	UpdateExternDomain=0
	if [ -n "$ServeExtZone" ]; then
		MasterExtDomainFile="$ZoneFilesFolder""db.""$FirstInternal"".""$CommunityExternDomain"
		ZoneTempFolder="$TempFolder""cache/""$CommunityExternDomain""/"
		cp -f "$ExternFile" "$CachedMasterFile""E"
		sed -i -e '/^\s*_dnsseckeys\./d' "$CachedMasterFile""E"
		[ -n "$(sed -e '/^\s*\(@\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Nn][Ss]\)\s/!d' "$CachedMasterFile""E")" ] || \
			sed -i -e 's/^\s*\(@\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Ss][Oo][Aa]\)\s\+\S\+\s\+\S\+\s/\1 '"$DNSSCRIPT_SERVER_NAME"'. '"$DNSSCRIPT_CONTACT_EMAIL"' /g' "$CachedMasterFile""E"
		
		sed -i -e 's/^\s*'"$CommunityExternPrefix"'\s/@ /g;/^\s*@\s\+[Ii][Nn]\s\+[Dd][Ss]\s/d' "$CachedMasterFile""E"
		
		UpdateExternDomain="$(UpdateDNSSECEntryCache "$CommunityExternDomain" "$ZoneTempFolder" "$CachedMasterFile""E" "$DNSSECKeyFolder")"
		[ $UpdateExternView -eq 0 ] || UpdateExternDomain=1
	
		if [ $UpdateExternDomain -ne 0 ]; then
			for KeyFile in "$ZoneTempFolder"*; do
				[ "$KeyFile" = "$ZoneTempFolder""*" ] || \
				cat "$KeyFile" >> "$CachedMasterFile""E"
	done
			LocalExtDomainMasterSerial="$(GetZoneFileSerial "$MasterExtDomainFile")"
			
			if [ $((LocalMasterSerial)) -le $((LocalExtDomainMasterSerial)) ]; then
				LocalExtDomainMasterSerial=$((LocalExtDomainMasterSerial+1))
				sed -i -e 's/^\(\s*\)'"$LocalMasterSerial"'\(\s*;\s*[Ss]erial.*\)$/\1'"$LocalExtDomainMasterSerial"'\3/g' "$CachedMasterFile""E"
				sed -i -e 's/^\(\s*\S\+\s\+\([0-9]*\s\)\?\s*[Ii][Nn]\s\+[Ss][Oo][Aa]\s\+\S\+\s\+\S\+\s\+\)'"$LocalMasterSerial"'\(\s\+.*\)$/\1'"$LocalExtDomainMasterSerial"'\3/g' "$CachedMasterFile""E"
			fi
			mv "$CachedMasterFile""E" "$MasterExtDomainFile"
			ReloadZone "$CommunityExternDomain" "$InternalViews"
		fi
		for IView in $InternalViews; do
			InternViewExternZone="$ZoneFilesFolder""db.""$IView"".""$CommunityExternDomain"
			[ -f "$InternViewExternZone" ] || ln -s "$MasterExtDomainFile" "$InternViewExternZone"
			InsertZoneToIncludeFile "$CommunityExternDomain" "$InternViewExternZone" "$TempFolder""$IView"".conf" "$DNSSECPolicy"
		done
		if [ -n "$ExternalView" ]; then
		ExternViewExternZone="$ZoneFilesFolder""db.""$ExternalView"".""$CommunityExternDomain"
			[ -f "$ExternViewExternZone" ] || ln -s "$MasterExtDomainFile" "$ExternViewExternZone"
			InsertZoneToIncludeFile "$CommunityExternDomain" "$ExternViewExternZone" "$TempFolder""$ExternalView"".conf" "$DNSSECPolicy"
	fi
	fi
fi

if [ -z "$MasterFile" ]; then
	MasterFile="$ZoneFilesFolder""db.""$FirstInternal"".""$CommunityDomain"
	cp -f "$CachedMasterFile" "$MasterFile"
fi

# set shorter TTL for Hoods
TTLReReExMi="420 360 180 1800 360"

Hoods="$(GetOwnHoods "$CommunityDomain" "$MasterFile")"

for Hood in $Hoods; do
	HoodDomain="${Hood%%\#*}"".""$CommunityDomain"
	Subnets="$(echo "${Hood#*\#}" | sed -e 's/#/ /g')"
	HoodZoneFile="$ZoneFilesFolder""db.""$FirstInternal"".""$HoodDomain"
	if [ ! -f "$HoodZoneFile" ]; then
		{
			echo "\$TTL ${TTLReReExMi%% *}"
			echo "@                           IN SOA    $DNSSCRIPT_SERVER_NAME""."" $DNSSCRIPT_CONTACT_EMAIL ("
			echo "                            1         ; Serial"
			echo "                            ""$(echo "$TTLReReExMi" | awk '{print $2}')""       ; Refresh"
			echo "                            ""$(echo "$TTLReReExMi" | awk '{print $3}')""       ; Retry"
			echo "                            ""$(echo "$TTLReReExMi" | awk '{print $4}')""      ; Expire"
			echo "                            ""$(echo "$TTLReReExMi" | awk '{print $5}')"" )     ; Negative Cache TTL"
			echo ";"
			echo "@                           IN NS     $DNSSCRIPT_SERVER_NAME""."""
			GetOwnGlueRecords "$CommunityDomain" "$HoodDomain" "$MasterFile"
			echo ";"
		} > "$HoodZoneFile"
	fi
	./update-hoodzone.sh "$HoodZoneFile" "$HoodDomain" "$Subnets" "$InternalViews"
	
	HoodForwardZones="$ForwardZones $HoodDomain""/""$HoodZoneFile"
	for Subnet in $Subnets; do
		ReverseDomains="$(GetReverseDomains "$Subnet")"
		for RDomain in $ReverseDomains; do
			ReverseZoneFileFullPath="$ZoneFilesFolder""$(GetReverseZoneFileFromZone "${RDomain%*.}")"
			./update-rdnszone.sh "$RDomain" "$HoodForwardZones" "$ReverseZoneFileFullPath" "$TTLReReExMi" "$InternalViews"
			for IView in $InternalViews; do
				InsertZoneToIncludeFile "${RDomain%*.}" "$ReverseZoneFileFullPath" "$TempFolder""$IView"".conf"
			done
		done
	done
	if [ -n "$CommunityExternDomain" ]; then
		HoodExternDomain="${Hood%%\#*}"".""$CommunityExternDomain"
	else
		HoodExternDomain=""
	fi
	ExternFile="$ZoneFilesFolder""db.""$ExternalView"".""$HoodDomain"
	./update-extzone.sh "$HoodZoneFile" "$ExternFile" "$HoodDomain" "$ExternalView"  "$HoodExternDomain" "$InternalViews"
	
	for IView in $InternalViews; do
		InternViewMasterZone="$ZoneFilesFolder""db.""$IView"".""$HoodDomain"
		[ -f "$InternViewMasterZone" ] || ln -s "$HoodZoneFile" "$InternViewMasterZone"
		InsertZoneToIncludeFile "$HoodDomain" "$InternViewMasterZone" "$TempFolder""$IView"".conf" "$DNSSECPolicy"
	done
	InsertZoneToIncludeFile "$HoodDomain" "$ExternFile" "$TempFolder""$ExternalView"".conf" "$DNSSECPolicy"
	
	if [ -n "$HoodExternDomain" ]; then
		for IView in $InternalViews; do
			InternViewExternZone="$ZoneFilesFolder""db.""$IView"".""${Hood%%\#*}"".""$CommunityExternDomain"
			[ -f "$InternViewExternZone" ] || ln -s "$ExternFile" "$InternViewExternZone"
			InsertZoneToIncludeFile "${Hood%%\#*}"".""$CommunityExternDomain" "$InternViewExternZone" "$TempFolder""$IView"".conf" "$DNSSECPolicy"
		done
		ExternViewExternZone="$ZoneFilesFolder""db.""$ExternalView"".""${Hood%%\#*}"".""$CommunityExternDomain"
		[ -f "$ExternViewExternZone" ] || ln -s "$ExternFile" "$ExternViewExternZone"
		InsertZoneToIncludeFile "${Hood%%\#*}"".""$CommunityExternDomain" "$ExternViewExternZone" "$TempFolder""$ExternalView"".conf" "$DNSSECPolicy"
	fi
done

#./update-public-acl.sh "$BindIcvpnAclTmp" "$RemoteLocation" "$RoutingTables"

ReConfigBind=0
UpdateBindConfig() {
	if [ -f "$1" ] && ! cmp -s "$1" "$2"; then
		mv "$1" "$2"
		ReConfigBind=1
	else
		rm -f "$1"
	fi
}

UpdateBindConfig "$BindIcvpnAclTmp" "$BindIcvpnAcl"
for IView in $InternalViews; do
	UpdateBindConfig "$TempFolder""$IView"".conf" "$BindIncludeFileFolder""$IView"".conf"
done
UpdateBindConfig "$TempFolder""$ExternalView"".conf" "$BindIncludeFileFolder""$ExternalView"".conf"

if [ $ReConfigBind -ne 0 ] || [ -f "/tmp/dnsscript-forcereconf" ]; then
	if [ $((DNSSCRIPT_BIND_RELOAD_VER)) -eq 0 ]; then
		systemctl restart bind9
	elif [ $((DNSSCRIPT_BIND_RELOAD_VER)) -eq 1 ]; then
		rndc reconfig
	elif [ $((DNSSCRIPT_BIND_RELOAD_VER)) -eq 2 ]; then
		/etc/init.d/named restart
	fi
	rm -f "/tmp/dnsscript-forcereconf"
fi

