# VEEAM_db_backup_via_vcenter

Der Ablauf bei HPE Storage Integration (BfSS)
Das folgende Schema verdeutlicht, wie Veeam den Hardware-Snapshot des HPE-Storages nutzt, um den VM-Stun-Effekt fast vollständig zu eliminieren:

VSS-Vorbereitung (Optional): Veeam weist das vCenter an, die VM über die VMware Tools kurz in einen konsistenten Zustand zu versetzen.

VMware-Snapshot: Es wird ein temporärer VMware-Snapshot erstellt (Dauer: wenige Millisekunden).

Hardware-Snapshot: Veeam triggert sofort über die HPE-API einen physischen Hardware-Snapshot auf dem Alletra- oder Primera-Storage.

VMware-Snapshot löschen: Der VMware-Snapshot wird sofort wieder gelöscht. Es entsteht keine Delta-Datei auf dem produktiven Datastore, die später zeitaufwendig konsolidiert werden müsste. Der "Stun-Effekt" wird somit auf ein nicht spürbares Minimum reduziert.

Transport: Das Alletra/Primera-System präsentiert den Hardware-Snapshot direkt an einen dedizierten Veeam Backup Proxy (via Fibre Channel oder iSCSI). Der Proxy liest die Daten direkt aus dem Storage-Snapshot und schreibt sie ins Backup-Repository. Die produktive VM merkt von diesem Datentransfer nichts.

Warum dieses Design die Netzwerksicherheit maximiert
Keine ausgehende Verbindung von der VM: Die VMs im Datenbank-VLAN benötigen 0 % Netzwerkzugriff auf den Veeam-Server oder das Repository. Auf der Firewall kann der gesamte ausgehende Datenverkehr von den VMs in das Backup-Netzwerk blockiert werden.

Kein Einfallstor bei Kompromittierung: Sollte eine Datenbank-VM gehackt werden, kann der Angreifer das Backup-System im Netzwerk weder sehen noch angreifen, da es keine Route dorthin gibt.

Sichere Steuerung: Die Steuerung des Backups erfolgt ausschließlich über das vCenter (auf Hypervisor-Ebene) und die Storage-Management-Schnittstellen (HPE-API), welche sich in einem separaten, hochsicheren Management-VLAN befinden sollten.

Schritt-für-Schritt-Konfiguration für HPE Alletra & Primera
Um dieses Design zu implementieren, müssen folgende Schritte durchgeführt werden:

1. HPE Storage in Veeam integrieren
Navigieren Sie in der Veeam-Konsole zu Storage Infrastructure -> Add Storage.

Wählen Sie Hewlett Packard Enterprise und anschließend HPE Alletra / Primera.

Geben Sie die Management-IP (DNS-Name) des Alletra- oder Primera-Systems an.

Hinterlegen Sie die Zugangsdaten für das Storage-System (ein dedizierter Benutzer auf dem Storage mit Rechten für Snapshot-Erstellung und -Export wird empfohlen).

Wählen Sie die entsprechende Protokollrolle (Fibre Channel oder iSCSI, je nachdem, wie die ESXi-Hosts angebunden sind).

2. Backup Proxy im SAN platzieren
Damit der Datentransfer direkt über das Storage-Netzwerk läuft, muss ein Veeam Backup Proxy direkten Zugriff auf das SAN haben:

Bei Fibre Channel (FC): Der Backup Proxy muss ein physischer Windows- oder Linux-Server mit einer HBA-Karte sein, die im selben FC-Zoning wie die Storage-Systeme liegt.

Bei iSCSI: Der Proxy kann eine VM sein, die über den Software-iSCSI-Initiator des Gast-Betriebssystems Zugriff auf das iSCSI-Netzwerk des Alletra/Primera-Storages hat.

3. Backup-Job konfigurieren
Erstellen Sie einen Standard-vSphere-Backup-Job in Veeam und fügen Sie die VMs hinzu.

Deaktivieren Sie unter Guest Processing die Option Enable application-aware processing, falls Sie jegliche Interaktion mit dem Gast-Betriebssystem vermeiden möchten (die Datenbanken werden dann absturzkonsistent gesichert, was für moderne Journaling-Dateisysteme und relationale Datenbanken dank des schnellen Storage-Snapshots meist unproblematisch ist).

Navigieren Sie zu Storage -> Advanced -> Reiter Integration.

Stellen Sie sicher, dass die Checkbox Enable backup from storage snapshots aktiviert ist.

1. Sorge: Die Datenkonsistenz (Absturzkonsistenz)Wenn Veeam die VM rein über das HPE-Storage-Plugin (ohne Gast-Interaktion) sichert, ist das Backup absturzkonsistent (crash-consistent).Was bedeutet das? Das Backup entspricht dem Zustand der VM, wenn man abrupt den Stecker zieht.Das Risiko: Moderne relationale Datenbanken (wie MariaDB, PostgreSQL und MS SQL) besitzen zwar ausgeklügelte Recovery-Mechanismen (wie das Journaling oder Write-Ahead-Logging) und starten nach einem Absturz in 99 % der Fälle fehlerfrei. Bei extrem schreibintensiven Datenbanken im hohen Transaktionsbereich besteht bei reiner Absturzkonsistenz dennoch ein Restrisiko für Datenverlust oder korrupte Tabellen.Die Lösung ohne Netzwerkzugriff:Nutzen Sie die lokale Skript-Ausführung von VMware Tools. Wenn in Veeam das VMware Tools Quiescing aktiviert ist, triggert der ESXi-Host über die VMware Tools lokale Skripte auf der VM – völlig ohne dass Veeam Zugangsdaten benötigt.Unter Linux sucht VMware Tools nach Skripten unter /usr/sbin/pre-freeze-script und /usr/sbin/post-thaw-script.Sie können über Ihr Uyuni (Salt) diese Skripte einmalig auf den VMs ablegen (z. B. um MariaDB kurz in den Read-Only-Modus zu versetzen).Der Ablauf: VMware Tools führt das lokale Skript aus (Datenbank friert ein) $\rightarrow$ HPE Primera erstellt den Storage-Snapshot $\rightarrow$ VMware Tools tauen die DB wieder auf.2. Sorge: Das "Log-Growth"-Problem (Speicherplatz)Dies ist die größere Gefahr bei einer "Sichern-und-Vergessen"-Mentalität ohne Gast-Zugriff.Das Problem: Datenbanken schreiben jede Änderung zuerst in ein Transaktionsprotokoll (MS SQL: .ldf, PostgreSQL: WAL-Files, MariaDB: Binlogs). Erst wenn ein erfolgreiches, anwendungskonsistentes Backup gemeldet wird, werden diese Protokolle abgeschnitten (truncated) oder gelöscht.Das Risiko: Da Veeam bei einem reinen Storage-Snapshot der Datenbank keinen erfolgreichen Backup-Abschluss signalisiert, wachsen diese Protokolldateien unaufhörlich weiter, bis die Festplatte der VM zu 100 % voll ist. Dann stürzt die Datenbank ab und verweigert den Dienst.Die Lösung für Ihre Datenbanken:Da Sie die VMs ohnehin mit Uyuni verwalten, lässt sich dieses Problem für die drei Datenbanktypen wie folgt zentral und automatisiert lösen:Microsoft SQL Server (unter Linux):Stellen Sie die SQL-Datenbanken auf das Simple Recovery Model um. In diesem Modus werden die Transaktionsprotokolle automatisch überschrieben und wachsen nicht unendlich an.MariaDB / MySQL:Verwenden Sie das in der vorherigen Antwort beschriebene Verfahren: Lassen Sie über einen lokalen Cronjob (z. B. alle 4 Stunden, kurz vor dem Veeam-Lauf) einen konsistenten Datenbank-Dump via mysqldump --single-transaction in ein lokales Verzeichnis schreiben. Das Alletra/Primera-Backup sichert dann diesen konsistenten Dump mit. Der Dump überschreibt sich jedes Mal selbst, sodass kein Speicherplatz-Problem entsteht.PostgreSQL:Ähnlich wie bei MariaDB können Sie lokale Cronjobs nutzen, um die WAL-Dateien (Write-Ahead-Logs) regelmäßig lokal zu bereinigen (z. B. via pg_archiveclean), da Veeam dies nicht für Sie übernehmen kann

Teil 1: Uyuni State für Datenkonsistenz (VMware Tools Integration)
VMware Tools sucht beim Einleiten des Quiescing-Vorgangs im Gast-Betriebssystem nach den Dateien /usr/sbin/pre-freeze-script und /usr/sbin/post-thaw-script.

Dieses Salt-State sorgt dafür, dass diese Skripte auf allen VMs mit den korrekten Berechtigungen angelegt werden. Die Skripte sorgen dafür, dass offene Transaktionen vor dem Snapshot auf die Festplatte geschrieben und Tabellen kurzzeitig gesperrt werden.

1.1 Salt State-Datei (/srv/salt/veeam_consistency.sls)

# =========================================================================
# Salt-State zur Absicherung der Datenkonsistenz waehrend des Backups.
# Dieses State installiert die Quiescing-Skripte fuer die VMware Tools.
# =========================================================================

# Sicherstellung, dass das Zielverzeichnis fuer die Skripte existiert
ensure_sbin_directory:
  file.directory:
    - name: /usr/sbin
    - user: root
    - group: root
    - mode: '0755'

# Bereitstellung des Pre-Freeze-Skripts zur Vorbereitung der Datenbanken
deploy_pre_freeze_script:
  file.managed:
    - name: /usr/sbin/pre-freeze-script
    - source: salt://veeam/files/pre-freeze-script
    - user: root
    - group: root
    - mode: '0700'
    - require:
      - file: ensure_sbin_directory

# Bereitstellung des Post-Thaw-Skripts zur Freigabe der Datenbanken
deploy_post_thaw_script:
  file.managed:
    - name: /usr/sbin/post-thaw-script
    - source: salt://veeam/files/post-thaw-script
    - user: root
    - group: root
    - mode: '0700'
    - require:
      - file: ensure_sbin_directory


1.2 Quellcodedatei: /srv/salt/veeam/files/pre-freeze-script
# =========================================================================
# Salt-State zur Absicherung der Datenkonsistenz waehrend des Backups.
# Dieses State installiert die Quiescing-Skripte fuer die VMware Tools.
# =========================================================================

# Sicherstellung, dass das Zielverzeichnis fuer die Skripte existiert
ensure_sbin_directory:
  file.directory:
    - name: /usr/sbin
    - user: root
    - group: root
    - mode: '0755'

# Bereitstellung des Pre-Freeze-Skripts zur Vorbereitung der Datenbanken
deploy_pre_freeze_script:
  file.managed:
    - name: /usr/sbin/pre-freeze-script
    - source: salt://veeam/files/pre-freeze-script
    - user: root
    - group: root
    - mode: '0700'
    - require:
      - file: ensure_sbin_directory

# Bereitstellung des Post-Thaw-Skripts zur Freigabe der Datenbanken
deploy_post_thaw_script:
  file.managed:
    - name: /usr/sbin/post-thaw-script
    - source: salt://veeam/files/post-thaw-script
    - user: root
    - group: root
    - mode: '0700'
    - require:
      - file: ensure_sbin_directory

1.3 Quellcodedatei: /srv/salt/veeam/files/post-thaw-script

#!/bin/bash
# =========================================================================
# POST-THAW SKRIPT FUER VMWARE TOOLS (QUIESCING)
# Dieses Skript wird unmittelbar nach der Erstellung des VM-Snapshots
# ausgefuehrt. Es gibt zuvor gesperrte Datenbank-Ressourcen wieder frei.
# =========================================================================

# Protokollierung des Startzeitpunkts
echo "$(date): Post-Thaw-Skript gestartet." >> /var/log/veeam-quiesce.log

# -------------------------------------------------------------------------
# 1. MARIADB / MYSQL
# -------------------------------------------------------------------------
if [ -f /tmp/mysql_freeze.pid ]; then
    echo "$(date): Hebe MariaDB/MySQL-Sperre auf..." >> /var/log/veeam-quiesce.log
    
    # Beendigung des im Hintergrund laufenden Sleep-Prozesses.
    # Dadurch wird die SQL-Verbindung getrennt und die Sperre aufgehoben.
    MYSQL_PID=$(cat /tmp/mysql_freeze.pid)
    kill "$MYSQL_PID"
    rm -f /tmp/mysql_freeze.pid
    echo "$(date): MariaDB/MySQL-Sperre erfolgreich aufgehoben." >> /var/log/veeam-quiesce.log
fi

# Fuer PostgreSQL und MS SQL Server sind an dieser Stelle keine weiteren
# Freigabeoperationen erforderlich, da keine blockierenden Locks gehalten wurden.

exit 0

Teil 2: Uyuni State für Log-Growth (Automatische Log-Bereinigung)
Da die Sicherung über die Speicher-Snapshots der HPE Alletra/Primera erfolgt, erhalten die Datenbanken keine direkte Rückmeldung über das erfolgreiche Backup. Die Transaktionsprotokolle würden daher unbegrenzt anwachsen.

Dieses State verteilt ein universelles Bereinigungsskript und richtet einen täglichen Cronjob ein, der die Protokolldateien aufräumt und komprimiert.

2.1 Salt State-Datei (/srv/salt/veeam_log_cleanup.sls)

# =========================================================================
# Salt-State zur Vermeidung von unkontrolliertem Log-Wachstum.
# Dieses State verteilt das Bereinigungsskript und richtet den Cronjob ein.
# =========================================================================

# Bereitstellung des universellen Bereinigungsskripts fuer alle DB-Typen
deploy_cleanup_script:
  file.managed:
    - name: /usr/local/bin/db_log_cleanup.sh
    - source: salt://veeam/files/db_log_cleanup.sh
    - user: root
    - group: root
    - mode: '0700'

# Einrichtung des taeglichen Cronjobs zur automatischen Ausfuehrung um 01:00 Uhr
configure_log_cleanup_cron:
  cron.present:
    - name: /usr/local/bin/db_log_cleanup.sh > /dev/null 2>&1
    - user: root
    - minute: '0'
    - hour: '1'
    - require:
      - file: deploy_cleanup_script

2.2 Quellcodedatei: /srv/salt/veeam/files/db_log_cleanup.sh

#!/bin/bash
# =========================================================================
# AUTOMATISIERTES DATENBANK-WARTUNGS- UND CLEANUP-SKRIPT
# Dieses Skript bereinigt die Transaktionsprotokolle der installierten
# Datenbanken, um ein Volllaufen der Festplatten zu verhindern.
# Es wird taeglich via Cron aufgerufen.
# =========================================================================

# Protokollierung des Wartungsstarts
echo "$(date): Taegliche Log-Bereinigung gestartet." >> /var/log/db-cleanup.log

# -------------------------------------------------------------------------
# 1. MICROSOFT SQL SERVER (LINUX)
# -------------------------------------------------------------------------
if systemctl is-active --quiet mssql-server; then
    echo "$(date): Bereinigung MS SQL Server..." >> /var/log/db-cleanup.log
    
    # Deklaration des sa-Passworts. Dieses sollte vorzugsweise aus einer
    # geschuetzten lokalen Konfigurationsdatei ausgelesen werden.
    SQL_PASSWORD="LokalesSicheresSAPasswort"
    
    # Automatisierte Umstellung aller Benutzerdatenbanken auf das
    # 'SIMPLE' Recovery Model. Dies verhindert dauerhaft das unbegrenzte
    # Anwachsen der .ldf-Dateien, da freigegebener Speicher ueberschrieben wird.
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SQL_PASSWORD" -C -Q "
        DECLARE @db_name NVARCHAR(255);
        DECLARE db_cursor CURSOR FOR 
        SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb');
        OPEN db_cursor;
        FETCH NEXT FROM db_cursor INTO @db_name;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC('ALTER DATABASE [' + @db_name + '] SET RECOVERY SIMPLE;');
            FETCH NEXT FROM db_cursor INTO @db_name;
        END;
        CLOSE db_cursor;
        DEALLOCATE db_cursor;
    " >> /var/log/db-cleanup.log 2>&1
fi

# -------------------------------------------------------------------------
# 2. MARIADB / MYSQL
# -------------------------------------------------------------------------
if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
    echo "$(date): Bereinigung MariaDB/MySQL..." >> /var/log/db-cleanup.log
    
    # Loeschen aller Binaerlogs (Binlogs), die aelter als 3 Tage sind.
    # Dies haelt ausreichend Transaktionsdaten fuer kurzfristige Replikationen
    # vor, verhindert jedoch die dauerhafte Belegung von Speicherplatz.
    mysql -u root -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 3 DAY;" >> /var/log/db-cleanup.log 2>&1
fi

# -------------------------------------------------------------------------
# 3. POSTGRESQL
# -------------------------------------------------------------------------
if systemctl is-active --quiet postgresql; then
    echo "$(date): Bereinigung PostgreSQL..." >> /var/log/db-cleanup.log
    
    # Loeschen von verwaisten und inaktiven Replikations-Slots.
    # Inaktive Replikations-Slots sind die haeufigste Ursache dafuer, dass
    # PostgreSQL die WAL-Dateien (Write-Ahead-Logs) unbegrenzt im Verzeichnis
    # 'pg_wal' aufstaut, da auf eine Bestaetigung des Clients gewartet wird.
    sudo -u postgres psql -c "
        SELECT pg_drop_replication_slot(slot_name) 
        FROM pg_replication_slots 
        WHERE active = false AND wal_status = 'lost';
    " >> /var/log/db-cleanup.log 2>&1
fi

echo "$(date): Taegliche Log-Bereinigung erfolgreich beendet." >> /var/log/db-cleanup.log
exit 0

Anwendung der Konfiguration über das Uyuni-Interface
Dateien auf dem Uyuni-Server ablegen:

Platzieren Sie die State-Dateien unter /srv/salt/veeam_consistency.sls und /srv/salt/veeam_log_cleanup.sls.

Erstellen Sie das Verzeichnis /srv/salt/veeam/files/ und legen Sie dort das pre-freeze-script, das post-thaw-script sowie das db_log_cleanup.sh ab.

Über Uyuni ausrollen:

Navigieren Sie in der Uyuni-Webkonsole zu Systems -> System Groups und wählen Sie die Gruppe Ihrer 500 VMs aus.

Gehen Sie zum Reiter Configuration -> Salt States.

Wählen Sie die beiden neu erstellten States veeam_consistency und veeam_log_cleanup aus und weisen Sie diese der Gruppe zu.

Klicken Sie auf Save und anschließend auf Apply Actions, um die Verteilung sofort und parallel anzustoßen.

