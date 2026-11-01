# docker_ffw-elw

Docker-Compose-Stack für den Server im Fahrzeug **MZF** der Feuerwehr Wörnitz. Er stellt im Fahrzeug MQTT, Telemetrie,
das Monitor-Dashboard, Livestream und Aufzeichnung der Kamera sowie den Einsatzdruck per E-Mail bereit. Erreichbar sind
die Dienste über das VPN unter `*.mzf.vpn.ffw-it.de`.

Das Repo enthält nur Konfiguration: `docker-compose.yml`, die Configs der Dienste und das Image für den RTMP-Server.
Secrets liegen in Dateien, die Git ignoriert (siehe [Einrichtung](#einrichtung)).

## Dienste

| Dienst            | Aufgabe                                                                                                        | Erreichbar über                                                           |
|-------------------|----------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------|
| `traefik`         | Reverse Proxy, TLS-Terminierung, Let's-Encrypt-Wildcard-Zertifikat per Hetzner-DNS                             | `80`, `443`, `8883`, `8884`; Dashboard: `traefik.mzf.vpn.ffw-it.de` (SSO) |
| `authentik_proxy` | Authentik-Outpost für das SSO, verbunden mit `auth.ffw-it.de`                                                  | intern, wird von Traefik angesprochen                                     |
| `watchtower`      | Meldet neue Image-Versionen, aktualisiert aber nichts selbst (`MONITOR_ONLY`)                                  | –                                                                         |
| `mqtt`            | Mosquitto-Broker, zentrale Datendrehscheibe                                                                    | siehe [MQTT](#mqtt)                                                       |
| `node-red`        | Automatisierung und Flows                                                                                      | `flow.mzf.vpn.ffw-it.de` (SSO)                                            |
| `web-monitor`     | Statische Monitor-Website aus `/opt/www-monitor-new`                                                           | `monitor.mzf.vpn.ffw-it.de` (SSO, ohne Login von `10.2.101.10`)           |
| `can-server`      | CAN-Daten des Fahrzeugs nach MQTT und InfluxDB ([`mzf-can2mqtt`](https://github.com/ff-woernitz/mzf-can2mqtt)) | intern                                                                    |
| `influxdb`        | Zeitreihen-Datenbank (InfluxDB 2)                                                                              | `influxdb.mzf.vpn.ffw-it.de` (eigener Login, kein SSO)                    |
| `telegraf`        | Sammelt Netflow/IPFIX und SNMP-Schnittstellennamen des Routers und schreibt sie in InfluxDB                    | `2055/udp`                                                                |
| `vlmcsd`          | KMS-Server                                                                                                     | `1688/tcp`                                                                |
| `zabbix_proxy`    | Aktiver Zabbix-Proxy, meldet an `z.tobsa.dev` und puffert bis zu 72 h offline                                  | ausgehend                                                                 |
| `email2print`     | Ruft ein Postfach per IMAP ab und druckt Anhänge auf `Einsatzdrucker_MZF` über das CUPS des Hosts              | ausgehend                                                                 |
| `rtmp`            | Nimmt den Kamerastream an, zeigt ihn per HLS im Browser und zeichnet ihn auf                                   | `1935`; Player: `stream.mzf.vpn.ffw-it.de` (SSO)                          |
| `gopro2mqtt`      | Steuert die GoPro per Bluetooth und MQTT ([`gopro2mqtt`](https://github.com/ff-woernitz/gopro2mqtt))           | intern                                                                    |

Alle Dienste hängen im Docker-Netz `backend` (`172.20.0.0/24`). Traefik veröffentlicht nur Container mit
`traefik.enable=true`.

## MQTT

Mosquitto bietet mehrere Listener mit getrennten Benutzern und ACLs:

| Port   | Protokoll                            | Zugriff                                   | Authentifizierung          |
|--------|--------------------------------------|-------------------------------------------|----------------------------|
| `1883` | MQTT                                 | nur im Docker-Netz                        | anonym                     |
| `8883` | MQTT über TLS (Traefik)              | von außen                                 | `listener_private/`        |
| `8884` | WebSocket über TLS (Traefik)         | von außen                                 | `listener_private/`        |
| `1884` | MQTT ohne TLS, direkt veröffentlicht | von außen, gedacht für Geräte im Fahrzeug | `listener_private_no_ssl/` |

Auf `8883` und `8884` terminiert Traefik das TLS. Die ACLs liegen im Repo, die `passwd`-Dateien nicht.

Optional lässt sich der Broker per Bridge mit den Servern der Feuerwehr koppeln. Vorlagen dafür sind die
`51-bridge-*.conf.example` in `mqtt-config/conf.d/`.

## Livestream und Aufzeichnung

1. Die Kamera sendet an `rtmp://<host>:1935/live/<stream-key>`. Senden darf nur das Subnetz `10.2.101.0/24`.
2. nginx-rtmp erzeugt daraus den HLS-Stream für den Player. Die Segmente liegen im `tmpfs`.
3. Zusätzlich wird jeder Stream nach `/opt/recordings` aufgezeichnet.
4. Nach dem Ende wandelt `rtmp/flv2mp4.sh` die Aufzeichnung in eine kleinere MP4 um und dreht das Bild um 180°, weil die
   Kamera kopfüber montiert ist. Die `.flv` wird erst nach erfolgreicher Umwandlung gelöscht.

`hls.js` wird beim Build ins Image kopiert, damit der Player im Fahrzeug auch ohne Internet läuft.

## Voraussetzungen

Auf dem Host:

- Docker mit Compose-Plugin
- CUPS mit dem Drucker `Einsatzdrucker_MZF` (`/var/run/cups/cups.sock`)
- D-Bus und Bluetooth für `gopro2mqtt`
- Die Verzeichnisse `/opt/www-monitor-new` (Monitor-Website) und `/opt/recordings` (Aufzeichnungen)

Extern:

- Hetzner-DNS für `ffw-it.de` (API-Token für die DNS-Challenge)
- Authentik-Server unter `auth.ffw-it.de` mit einem Outpost für diesen Stack
- Zabbix-Server unter `z.tobsa.dev`

## Einrichtung

1. Secrets aus den Vorlagen anlegen und ausfüllen:

   ```bash
   cp .env.example .env
   cp authentik.env.example authentik.env
   cp email2print.env.example email2print.env
   cp gopro2mqtt.env.example gopro2mqtt.env
   ```

2. `telegraf.conf` mit InfluxDB-Token und SNMP-Community ausfüllen (Vorlage: `telegraf.conf.example`).

3. `can-server.toml` im Repo-Root anlegen. (Vorlage: `can-server.toml.example`)

4. MQTT-Passwörter anlegen. Mosquitto braucht beide `passwd`-Dateien zum Start. `-c` legt die Datei neu an, für weitere
   Benutzer entfällt der Schalter:

   ```bash
   docker compose run --rm mqtt mosquitto_passwd -c /mosquitto/config/listener_private/passwd <benutzer>
   docker compose run --rm mqtt mosquitto_passwd -c /mosquitto/config/listener_private_no_ssl/passwd <benutzer>
   ```

   Jeder Benutzer braucht außerdem einen Eintrag in der passenden `acl`-Datei.

5. Optional die MQTT-Bridges aktivieren, indem die `.example`-Dateien ohne diese Endung kopiert werden.

6. Stack starten:

   ```bash
   docker compose up -d --build
   ```

## Betrieb

Das Skript `update` aktualisiert den Stack:

```bash
./update
```

Es sichert zuerst den aktuellen Zustand nach `backups/<datum>.backup`, baut und zieht dann die Images und fragt vor dem
Neustart der Container nach. Die Backups enthalten die Ausgabe von `docker compose config` und damit auch aufgelöste
Secrets. Sie sind von Git ausgeschlossen und sollten nicht weitergegeben werden. Die Datei sichert nur den Zustand der
Konfiguration, nicht die Daten in den Volumes.

Die Version von `authentik_proxy` ist in `docker-compose.yml` fest eingetragen und wird von Hand angehoben. Sie sollte
zur Version des Authentik-Servers passen.

## Aufbau des Repos

```text
.
├── docker-compose.yml     Alle Dienste
├── update                 Backup und Update des Stacks
├── *.env.example          Vorlagen für die Secrets
├── telegraf.conf          Telegraf-Konfiguration
├── mqtt-config/           Mosquitto: Listener, ACLs, Bridge-Vorlagen
├── rtmp/                  Image für Stream und Aufzeichnung, inkl. Player
└── traefik/               Statische und dynamische Traefik-Konfiguration
```
