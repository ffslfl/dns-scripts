
# ffslfl-scripts
Dieses Git enthält eine Sammlung an Scripten zur Aktualisierung des Zone-git für ffslfl.community.
Außerdem gibt es Skripte, die aus der Forward-Zone eine passende Reverse-Zone für unsere internen RFC 1918 und RFC 4193 Adressen erzeugen.

## Installation
#### Zone-git klonen
Zuerst muss das [dns-git](https://github.com/ffslfl/dns) geclont werden. Dieses enthält die Zonendatei für ffslfl.community. Wohin dieses git geklont wird, ist egal. Der DNS Server muss Lesezugriff darauf haben.
```
git clone https://github.com/ffslfl/dns.git /srv/ffslfl-dns
```

#### dns-scripts klonen
Dann können die Skripte geklont werden. Dabei ist aktuell noch die Position wichtig, da das Skript derzeit absolulte Pfade verwendet.
```
git clone https://github.com/ffslfl/dns-scripts.git /srv/ffslfl-scripts
```

#### Cron anlegen
Schließlich muss noch ein Cron angelegt werden, der regelmäßig das Skript aufruft, welches das Zone-git aktualisiert und die Reverse-Skripte aufruft:
```
1-59/5 *   * * *   /srv/ffslfl-scripts/update-dns.sh /srv/ffslfl-dns
```

#### DNS-Server konfigurieren
Dann muss nur noch der DNS Server, z.B. `bind`, für die entsprechenden Zonen eingerichtet werden:
```
$ cat named.conf.local 
[..]

zone "24.10.in-addr.arpa" {
    type master;
    file "/var/lib/bind/db.24.10";
    allow-query { any; };
};
zone "e.2.7.5.e.a.6.9.7.0.d.f.ip6.arpa" {
    type master;
    file "/var/lib/bind/db.fd07-96ae-572e";
    allow-query { any; };
};

zone "ffslfl.community" {
    type master;
    file "/srv/ffslfl-dns/db.ffslfl.community";
    allow-query { any; };
};

[..]
```
