
# ffslfl-scripts
Dieses Git enthält eine Sammlung an Scripten zur Aktualisierung der Zonen für ffslfl.community.Dabei werden aus der Forward-Zone und optional eigener Subdomain (durch community-Zonefile gesteuert) auch passende Reverse-Zonen für unsere internen RFC 1918 und RFC 4193 Adressen erzeugen.

Weiterhin werden bei eigener Subdomain die momentan vergebenen Adressen von dnsmasq und odhcpd (alles unter /tmp/hosts/) inkludiert.
Das ermöglicht eine Namensauflösung für Freifunk-Teilnehmer ohne manuelle Konfiguration.
Damit kann jeder Freifunk-Teilnehmer ein gültiges TLS-Zertifikat bekommen, sofern DHCPv6 am Gateway aktiviert ist.

DNSSEC wird für jede Zone unterstützt, allerdings nur für die Hauptzone mit mehreren Servern. Für Subdomainserver darf mit DNSSEC nur jeweils ein Server authorativ sein.

## Installation

#### Systemanforderungen

curl

named-checkzone (z.B. bei bind oder bind-tools enthalten)

```
echo "dump" | nc ::1 33123
```
muss die babel routen ausgeben, ansonsten muss update-public-acl.sh angepasst werden

#### dns-scripts klonen
Die Scripte müssen geklont werden, oder anderweitig in einem Ordner auf dem Server abgelegt werden. Dabei ist aktuell noch die Position wichtig, da das Skript derzeit absolute Pfade verwendet (oder den Pfad in update-dns.sh anpassen)
```
git clone https://github.com/ffslfl/dns-scripts.git /usr/lib/ffslfldns
```

#### konfigurieren
In der Datei update-dns.sh die Konfigurationsparameter setzen.


#### Cron anlegen
Schließlich muss noch ein Cron angelegt werden, der regelmäßig das Skript aufruft:
```
1-59/5 *   * * *   /usr/lib/ffslfldns/update-dns.sh
```

#### DNS-Server konfigurieren
Dann muss nur noch der DNS Server, z.B. `bind`, eingerichtet werden.

Für bind werden durch die Scripte die include-Dateien angelegt (ffslfl.community-[in|ex]ternal.conf|icvpn-acl.conf):

Konfiguration:

```
$ cat named.conf.local 
[..]

acl icvpnlocal {
	10.0.0.0/8;
	172.16.0.0/12;
	fc00::/7;
};
include "/etc/bind/icvpn-acl.conf"; # auto-generated

[..]

options {
	[..] # eigene Optionen

	check-names master warn; # Wichtig, da sonst Hostnamen mit _ (z.B.: HUAWEI_P30_lite ) bind nicht laden lassen
}

[..]

view "icvpn-internal-view" {    
	match-clients { icvpnrange; localhost; };
	allow-query-cache { any; }

    [..] # eigene Optionen


	include "/etc/bind/icvpn-internal-view.conf"; # auto-generated

	include "/etc/bind/icvpn-zones.conf"; # Nicht vergessen ;)

    [..]	
};

view "external-view" {
	match-clients { any; };
    [..] # eigene Optionen
	
	include "/etc/bind/external-view.conf"; # auto-generated
    
    [..]	
};


[..]
```
