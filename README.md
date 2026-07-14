# HPE Storage-integrierte, passwortlose & stun-freie Backup-Architektur für Linux-Datenbanken via Veeam & Uyuni

Dieses Repository enthält die vollständige Konfiguration, die Salt-States für **Uyuni (SaltStack)** und die lokalen Skripte zur Implementierung einer hochsicheren, performanten und vollständig automatisierten Backup-Architektur für über 500 Linux-VMs mit relationalen Datenbanken (**MariaDB/MySQL, PostgreSQL, MS SQL Server**).

## 1. Architektur und Design-Entscheidungen

Bei einer Infrastruktur von über 500 virtuellen Maschinen mit geschäftskritischen Datenbanken müssen klassische Backup-Konzepte überdacht werden. Das hier implementierte Design löst zwei fundamentale Konflikte:

### Konflikt A: Sicherheit vs. Offene Netzwerkports (Lateral Movement)
* **Problem:** Herkömmliche agentenbasierte Backups erfordern entweder die Speicherung administrativer Zugangsdaten auf dem zentralen Veeam-Server (Sicherheitsrisiko bei Kompromittierung des Backup-Servers) oder die Öffnung von Outbound-Netzwerkports von den produktiven VMs in Richtung Backup-Infrastruktur (Risiko von Lateral Movement bei einer Kompromittierung einer produktiven VM).
* **Lösung (Design 1 - Pull-Verfahren):** Vollständige Blockierung jeglichen Netzwerkverkehrs aus dem Datenbank-VLAN in das Backup-VLAN auf Firewall-Ebene. Veeam greift ausschließlich über das vCenter und die Management-Schnittstellen des HPE-Speichersystems zu. Die VMs sind netzwerktechnisch zu 100 % isoliert und initiieren keine Verbindungen nach außen.

### Konflikt B: Datenkonsistenz vs. Latenzen im Millisekundenbereich (VM-Stun)
* **Problem:** Das Erstellen und insbesondere das Löschen (Konsolidieren) von VMware-Snapshots führt bei schreibintensiven Datenbanken zu spürbaren Latenzeinbrüchen (dem sogenannten "VM-Stun-Effekt"). Für Echtzeit-Anwendungen mit Latenzanforderungen im Millisekundenbereich ist dies inakzeptabel.
* **Lösung:** Einsatz von **Veeam Backup from Storage Snapshots (BfSS)** in Kombination mit **HPE Alletra** und **HPE Primera** Speichersystemen. Der VMware-Snapshot existiert nur für Bruchteile einer Sekunde. Die eigentliche Datenübertragung erfolgt hardwareseitig direkt aus dem Storage-Snapshot über das SAN an den Veeam Backup Proxy.

---

## 2. Technische Hürden & deren Lösung auf Betriebssystemebene

Da das Backup out-of-band über Speicher-Snapshots erfolgt und Veeam keinen direkten Systemzugriff besitzt, ergeben sich zwei Herausforderungen auf Betriebssystemebene:

1.  **Datenkonsistenz (Application Consistency):** Die Datenbanken müssen kurzzeitig in einen konsistenten Zustand versetzt werden, bevor der Snapshot erstellt wird, ohne dass Veeam Zugangsdaten benötigt.
    * *Lösung:* Nutzung der lokalen VMware Tools Schnittstelle. Vor dem Snapshot führt der ESXi-Host über die VMware Tools die lokalen Skripte `pre-freeze-script` und `post-thaw-script` als `root` aus.
2.  **Unkontrolliertes Log-Wachstum (Log-Growth):** Da die Datenbanken keine direkte Erfolgsmeldung vom Backup-Server erhalten, werden die Transaktionsprotokolle (WAL, Binlogs, LDF) nicht automatisch bereinigt und würden die Festplatten füllen.
    * *Lösung:* Ein täglicher, lokaler Cronjob (`db_log_cleanup.sh`), der das Log-Wachstum kontrolliert, indem er Datenbanken auf das *Simple Recovery Model* umstellt (MS SQL) oder alte Log-Dateien sicher bereinigt (MariaDB, PostgreSQL).

---

## 3. Struktur des Repositories

Die Bereitstellung und Wartung auf allen 500 Linux-VMs erfolgt vollautomatisch über **Uyuni (SaltStack)**.

```text
.
├── salt/
│   ├── veeam_consistency.sls      # Salt State für die Konsistenz-Skripte
│   └── veeam_log_cleanup.sls      # Salt State für den täglichen Wartungs-Cronjob
└── files/
    ├── pre-freeze-script          # VMware Tools Skript vor dem Snapshot
    ├── post-thaw-script           # VMware Tools Skript nach dem Snapshot
    └── db_log_cleanup.sh          # Universelles Log-Bereinigungsskript (Cron)
