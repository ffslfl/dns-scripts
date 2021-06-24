#!/bin/bash
#Name der Zone
DomainZone="e.2.7.5.e.a.6.9.7.0.d.f.ip6.arpa."
#Positionen und Namen der Forward Lookup Zone Files
ForwardZoneFiles=("/srv/ffslfl-dns/db.ffslfl.community")
ReverseZoneFile="/var/lib/bind/db.fd07-96ae-572e"
#Temporäres Verzeichnis - muss pro Zone exclusiv sein!
TempDir="/tmp/e.2.7.5.e.a.6.9.7.0.d.f.ip6.arpa"
#TTL
TTL=3600
#refresh
refresh=2000
#retry
retry=6400
#expire
expire=2419200
#minimum
minimum=86400
#contact-mail
contact=schleswig-flensburg.freifunk.net.
#responsible DNS Server by name (for reverseDNS your own)
responsible=ffslfl.community.

#################################################################

function dnsreload {
	systemctl reload bind9
}

function validate_ip() {
	local  ip=$1
	local  stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
			&& ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
	fi
	return $stat
}


mkdir -p $TempDir
Serials=()
for ForwardZoneFile in "${ForwardZoneFiles[@]}"
do
	ZoneName=$(cat $ForwardZoneFile | grep SOA | awk '{ print $1 }' | head -n 1)
	named-compilezone -o "$TempDir/$ZoneName" $ZoneName $ForwardZoneFile >/dev/null 2>&1
	serial=$(cat "$TempDir/$ZoneName" | grep SOA | awk '{ print $7 }' | head -n 1)
	Serials+=( "$serial" )
done

Serials=( $( for i in ${Serials[@]}; do echo "$i"; done | sort -rn ) )
serial=${Serials[0]}

echo "$DomainZone $TTL IN SOA $responsible $contact $serial $refresh $retry $expire $minimum" > "$TempDir/$DomainZone"
echo "$DomainZone $TTL IN NS $responsible" >> "$TempDir/$DomainZone"
for ForwardZoneFile in $(ls $TempDir)
do
	Hosts=($(cat "$TempDir/$ForwardZoneFile" | grep -v SOA | grep -Fv "*" | awk '{ print $1 }'))
	IPs=$(cat "$TempDir/$ForwardZoneFile" | grep -v SOA | grep -Fv "*" | awk '{ print $5 }')
	i=0
	for IP in $IPs; do
		if rdns=$(sipcalc -r "$IP" | grep -F "ip6.arpa."); then
			echo "$rdns $TTL IN PTR ${Hosts[$i]}" >> "$TempDir/$DomainZone"
		fi
		i=$((i+1))
	done
done

if [ -f $ReverseZoneFile ]; then
		oldSerial=$(grep SOA $ReverseZoneFile | awk 'NR==1{print $7}')
else
		oldSerial=0
fi

if [ $serial -gt $oldSerial ]
then
	named-compilezone -o $ReverseZoneFile $DomainZone "$TempDir/$DomainZone" >/dev/null 2>&1
	dnsreload
fi
rm -r $TempDir

