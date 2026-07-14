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
    # Hinweis: Die Spalte 'wal_status' erfordert PostgreSQL 13 oder neuer.
    # Bei aelteren Versionen kann die Bedingung 'active = false' ausreichen.
    sudo -u postgres psql -c "
        SELECT pg_drop_replication_slot(slot_name) 
        FROM pg_replication_slots 
        WHERE active = false AND wal_status = 'lost';
    " >> /var/log/db-cleanup.log 2>&1
fi

echo "$(date): Taegliche Log-Bereinigung erfolgreich beendet." >> /var/log/db-cleanup.log
exit 0
