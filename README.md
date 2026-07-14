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

Die Bereitstellung und Wartung auf allen Linux-VMs erfolgt vollautomatisch über **Uyuni (SaltStack)**.

```text
.
├── salt/
│   ├── veeam_consistency.sls      # Salt State für die Konsistenz-Skripte
│   └── veeam_log_cleanup.sls      # Salt State für den täglichen Wartungs-Cronjob
└── files/
    ├── pre-freeze-script          # VMware Tools Skript vor dem Snapshot
    ├── post-thaw-script           # VMware Tools Skript nach dem Snapshot
    └── db_log_cleanup.sh          # Universelles Log-Bereinigungsskript (Cron)
---
```

## Bereitstellung via Uyuni
Dateien auf dem Uyuni-Server ablegen:
Kopieren Sie die Salt-State-Dateien (.sls) in das Verzeichnis `/srv/salt/` des Salt-Masters. Erstellen Sie das Verzeichnis `/srv/salt/veeam/files/` und legen Sie dort die Skripte ab.

State zuweisen:
Weisen Sie die States `veeam_consistency` and `veeam_log_cleanup` in der Uyuni-Weboberfläche der gewünschten Systemgruppe (z. B. grp_db_backup_veeam) zu.

Änderungen anwenden:
Führen Sie die Aktion Apply Actions in Uyuni aus, um die Konfiguration parallel auf allen VMs anzuwenden.

### 2. Die Skripte einzeln zur Ablage im Repository

Legen Sie die folgenden Dateien gemäß der beschriebenen Ordnerstruktur in Ihrem Git-Repository oder direkt auf dem Uyuni-Server (Salt-Master) unter `/srv/salt/` an.

#### Datei 1: `salt/veeam_consistency.sls`
*Zielpfad auf dem Uyuni-Server:* `/srv/salt/veeam_consistency.sls`


