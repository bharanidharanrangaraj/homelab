#!/usr/bin/env bash
# IoT Studio — restore the database from a backup made by iotstudio-backup.
#
#   sudo iotstudio-restore /opt/iotstudio/backups/db-20260101-023000.sql.gz
#
# DESTROYS the current database contents. Stops the app, restores, starts it again.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0 <backup.sql.gz>"; exit 1; }
FILE="${1:-}"; [ -f "$FILE" ] || { echo "Usage: $0 <backup.sql.gz>"; exit 1; }
read -r -p "This REPLACES the current database with $FILE. Type YES to continue: " ans
[ "$ans" = "YES" ] || { echo "Cancelled."; exit 1; }
set -a; . /opt/iotstudio/.env; set +a
systemctl stop iotstudio-backend iotstudio-worker
sudo -u postgres psql -qc "DROP DATABASE IF EXISTS iotstudio" -c "CREATE DATABASE iotstudio OWNER iotstudio"
gunzip -c "$FILE" | sudo -u postgres psql -q -d iotstudio >/dev/null
sudo -u postgres psql -qd iotstudio -c "ALTER SCHEMA public OWNER TO iotstudio" -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO iotstudio" -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO iotstudio"
systemctl start iotstudio-backend iotstudio-worker
echo "Restored. The next backend start re-creates any missing MQTT accounts automatically."
