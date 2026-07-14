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
