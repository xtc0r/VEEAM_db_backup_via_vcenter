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
# Ausgabe wird ins Logfile umgeleitet (nicht nach /dev/null), damit Fehler
# sichtbar bleiben und ueber Uyuni/Logwatch ausgewertet werden koennen.
configure_log_cleanup_cron:
  cron.present:
    - name: /usr/local/bin/db_log_cleanup.sh >> /var/log/db-cleanup.log 2>&1
    - user: root
    - minute: '0'
    - hour: '1'
    - require:
      - file: deploy_cleanup_script