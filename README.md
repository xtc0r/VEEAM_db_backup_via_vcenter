# HPE Storage-integrierte, passwortlose & stun-freie Backup-Architektur für Linux-Datenbanken via Veeam & Uyuni

Dieses Repository enthält die vollständige Konfiguration, die Salt-States für **Uyuni (SaltStack)** und die lokalen Skripte zur Implementierung einer hochsicheren, performanten und vollständig automatisierten Backup-Architektur für über 500 Linux-VMs mit relationalen Datenbanken (**MariaDB/MySQL, PostgreSQL, MS SQL Server**).

## 1. Architektur und Design-Entscheidungen

Bei einer Infrastruktur von über 500 virtuellen Maschinen mit geschäftskritischen Datenbanken müssen klassische Backup-Konzepte überdacht werden. Das hier implementierte Design löst zwei fundamentale Konflikte:

### Konflikt A: Sicherheit vs. Offene Netzwerkports (Lateral Movement)
- **Problem:** Herkömmliche agentenbasierte Backups erfordern entweder die Speicherung administrativer Zugangsdaten auf dem zentralen Veeam-Server (Sicherheitsrisiko bei Kompromittierung des Backup-Servers) oder die Öffnung von Outbound-Netzwerkports von den produktiven VMs in Richtung Backup-Infrastruktur (Risiko von Lateral Movement bei einer Kompromittierung einer produktiven VM).
- **Lösung (Design 1 - Pull-Verfahren):** Vollständige Blockierung jeglichen Netzwerkverkehrs aus dem Datenbank-VLAN in das Backup-VLAN auf Firewall-Ebene. Veeam greift ausschließlich über das vCenter und die Management-Schnittstellen des HPE-Speichersystems zu. Die VMs sind netzwerktechnisch zu 100 % isoliert und initiieren keine Verbindungen nach außen.

### Konflikt B: Datenkonsistenz vs. Latenzen im Millisekundenbereich (VM-Stun)
- **Problem:** Das Erstellen und insbesondere das Löschen (Konsolidieren) von VMware-Snapshots führt bei schreibintensiven Datenbanken zu spürbaren Latenzeinbrüchen (dem sogenannten "VM-Stun-Effekt"). Für Echtzeit-Anwendungen mit Latenzanforderungen im Millisekundenbereich ist dies inakzeptabel.
- **Lösung:** Einsatz von **Veeam Backup from Storage Snapshots (BfSS)** in Kombination mit **HPE Alletra** und **HPE Primera** Speichersystemen. Der VMware-Snapshot existiert nur für Bruchteile einer Sekunde. Die eigentliche Datenübertragung erfolgt hardwareseitig direkt aus dem Storage-Snapshot über das SAN an den Veeam Backup Proxy.

---

## 2. Technische Hürden & deren Lösung auf Betriebssystemebene

Da das Backup out-of-band über Speicher-Snapshots erfolgt und Veeam keinen direkten Systemzugriff besitzt, ergeben sich zwei Herausforderungen auf Betriebssystemebene:

1. **Datenkonsistenz (Application Consistency):** Die Datenbanken müssen kurzzeitig in einen konsistenten Zustand versetzt werden, bevor der Snapshot erstellt wird, ohne dass Veeam Zugangsdaten benötigt.
   - *Lösung:* Nutzung der lokalen VMware Tools Schnittstelle. Vor dem Snapshot führt der ESXi-Host über die VMware Tools die lokalen Skripte `pre-freeze-script` und `post-thaw-script` als `root` aus.

2. **Unkontrolliertes Log-Wachstum (Log-Growth):** Da die Datenbanken keine direkte Erfolgsmeldung vom Backup-Server erhalten, werden die Transaktionsprotokolle (WAL, Binlogs, LDF) nicht automatisch bereinigt und würden die Festplatten füllen.
   - *Lösung:* Ein täglicher, lokaler Cronjob (`db_log_cleanup.sh`), der das Log-Wachstum kontrolliert.

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
```

---

## 4. Bereitstellung via Uyuni

### 4.1 Dateien auf dem Uyuni-Server ablegen
Kopieren Sie die Salt-State-Dateien (.sls) in das Verzeichnis `/srv/salt/` des Salt-Masters. Erstellen Sie das Verzeichnis `/srv/salt/veeam/files/` und legen Sie dort die Skripte ab.

### 4.2 State zuweisen
Weisen Sie die States `veeam_consistency` und `veeam_log_cleanup` in der Uyuni-Weboberfläche der gewünschten Systemgruppe (z. B. `grp_db_backup_veeam`) zu.

### 4.3 Änderungen anwenden
Führen Sie die Aktion **Apply Actions** in Uyuni aus, um die Konfiguration parallel auf allen VMs anzuwenden.

---

## 5. Voraussetzungen und Konfiguration

### 5.1 SA-Passwort für MS SQL Server
Die Skripte (`pre-freeze-script` und `db_log_cleanup.sh`) benötigen für MS SQL Server das SA-Passwort. Hinterlegen Sie dieses auf jeder VM in einer geschützten Konfigurationsdatei:

```bash
echo 'MeinSicheresSAPasswort' | sudo tee /etc/veeam/mssql_backup.conf
sudo chmod 600 /etc/veeam/mssql_backup.conf
```

### 5.2 MariaDB/MySQL root-Zugriff
Die Skripte setzen auf passwortlosen root-Zugriff via UNIX-Socket-Plugin (`auth_socket`) oder `~/.my.cnf` voraus. Standard auf Debian/Ubuntu. Bei anderen Distributionen ggf. konfigurieren.

### 5.3 PostgreSQL
Das Skript nutzt `sudo -u postgres psql` und setzt voraus, dass der postgres-Systembenutzer ohne Passwort zugreifen kann (Standardkonfiguration).

---

## 6. Hinweise zu den Skripten

### 6.1 Point-in-Time Recovery (PITR) bei MS SQL Server
Das Skript `db_log_cleanup.sh` schaltet alle MS SQL-Benutzerdatenbanken auf das **SIMPLE Recovery Model**. Dies verhindert unbegrenztes .ldf-Wachstum, deaktiviert jedoch die Point-in-Time Recovery (PITR) für diese Datenbanken.

**Alternative mit PITR-Erhalt:**
Ersetzen Sie den `ALTER DATABASE ... SET RECOVERY SIMPLE`-Block durch:
```sql
BACKUP LOG [db_name] TO DISK = '/var/opt/mssql/backup/[db_name]_log.trn';
DBCC SHRINKFILE ([db_name]_log, 100);
```
Dies erfordert ausreichend Speicherplatz für Log-Backup-Dateien und eine separate Aufräumlogik für alte Backups.

### 6.2 PostgreSQL Crash Recovery
Der `pre-freeze-script` verwendet für PostgreSQL einen CHECKPOINT, nicht `pg_start_backup()`. Bei Storage-Snapshots (HPE BfSS) ist dies ausreichend, da PostgreSQL beim Restore automatisch in den Crash-Recovery-Modus geht und die WAL-Transaktionslogs bis zum Snapshot-Zeitpunkt einspielt.

### 6.3 MS SQL Server fsfreeze
MS SQL Server unter Linux reagiert **nicht** automatisch auf den Hypervisor-fsfreeze (anders als unter Windows mit VSS). Das `pre-freeze-script` führt daher manuell einen CHECKPOINT via `sqlcmd` aus.