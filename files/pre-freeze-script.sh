#!/bin/bash
# =========================================================================
# PRE-FREEZE SKRIPT FUER VMWARE TOOLS (QUIESCING)
# Dieses Skript wird unmittelbar vor der Erstellung des VM-Snapshots
# ausgefuehrt. Es identifiziert die aktive Datenbank und versetzt diese
# in einen konsistenten Zustand.
# =========================================================================

# Protokollierung des Startzeitpunkts
echo "$(date): Pre-Freeze-Skript gestartet." >> /var/log/veeam-quiesce.log

# -------------------------------------------------------------------------
# 1. MARIADB / MYSQL
# -------------------------------------------------------------------------
if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
    echo "$(date): MariaDB/MySQL erkannt. Tabellen werden gesperrt..." >> /var/log/veeam-quiesce.log
    
    # Erstellung einer Sperre im Hintergrund. Die Verbindung muss geoeffnet
    # bleiben, da die Sperre (READ LOCK) an die aktive Session gebunden ist.
    # Ein Sleep-Wert von 600 Sekunden dient als maximale Sicherheitsgrenze.
    # Es wird vorausgesetzt, dass die Authentifizierung fuer den root-Kontext
    # ueber das UNIX-Socket-Plugin oder eine lokale '.my.cnf'-Konfigurationsdatei
    # passwortlos konfiguriert ist.
    mysql -u root -e "FLUSH TABLES WITH READ LOCK; SELECT SLEEP(600);" &
    
    # Speicherung der Prozess-ID, um die Verbindung im Thaw-Skript zu beenden
    echo $! > /tmp/mysql_freeze.pid
    
    # Kurze Verzoegerung, um die Etablierung des Locks sicherzustellen
    sleep 2
fi

# -------------------------------------------------------------------------
# 2. POSTGRESQL
# -------------------------------------------------------------------------
if systemctl is-active --quiet postgresql; then
    echo "$(date): PostgreSQL erkannt. Checkpoint wird erzwungen..." >> /var/log/veeam-quiesce.log
    
    # Ein manueller Checkpoint schreibt alle geänderten Daten (dirty pages)
    # aus dem Arbeitsspeicher direkt auf die Festplatte, was die Konsistenz
    # maximiert und die Recovery-Zeit im Wiederherstellungsfall minimiert.
    # Dieses Verfahren ist fuer Storage-Snapshots extrem sicher und stabil.
    sudo -u postgres psql -c "CHECKPOINT;" >> /var/log/veeam-quiesce.log 2>&1
fi

# -------------------------------------------------------------------------
# 3. MICROSOFT SQL SERVER (LINUX)
# -------------------------------------------------------------------------
if systemctl is-active --quiet mssql-server; then
    echo "$(date): MS SQL Server (Linux) erkannt. Keine manuellen Skript-Aktionen erforderlich." >> /var/log/veeam-quiesce.log
    # Der MS SQL Server unter Linux registriert sich nativ im Betriebssystem
    # und reagiert automatisch auf den vom Hypervisor ausgeloesten
    # fsfreeze-Befehl. Manuelle Skript-Eingriffe sind nicht notwendig.
fi

exit 0
