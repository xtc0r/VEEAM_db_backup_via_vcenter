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
