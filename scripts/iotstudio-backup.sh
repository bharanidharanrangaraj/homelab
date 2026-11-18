#!/usr/bin/env bash
# IoT Studio — database backup (PostgreSQL) + broker accounts file. Runs nightly from cron, and before every update.
#
#   iotstudio-backup
#
# Keeps the newest 30 backups in /opt/iotstudio/backups. For an off-site copy set one of these in /opt/iotstudio/.env:
#   DL_BACKUP_RSYNC=user@backup-host:/path/        (rsync over SSH)
#   DL_BACKUP_RCLONE=remote:bucket/iotstudio       (any rclone remote: Google Drive, OneDrive, S3 ...)
set -euo pipefail
APP=/opt/iotstudio
DIR=$APP/backups
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$DIR"
set -a; . "$APP/.env"; set +a
OUT="$DIR/db-$STAMP.sql.gz"
pg_dump --no-owner --no-privileges "$DL_DATABASE_URL" | gzip -9 > "$OUT"
[ -s "$OUT" ] || { echo "Backup is empty!"; rm -f "$OUT"; exit 1; }
[ -f /var/lib/mosquitto/dynamic-security.json ] && cp /var/lib/mosquitto/dynamic-security.json "$DIR/mqtt-accounts-$STAMP.json"
chown -R iotstudio:iotstudio "$DIR" 2>/dev/null || true
chmod 600 "$DIR"/* 2>/dev/null || true
ls -1t "$DIR"/db-*.sql.gz | tail -n +31 | xargs -r rm -f
ls -1t "$DIR"/mqtt-accounts-*.json 2>/dev/null | tail -n +31 | xargs -r rm -f
if [ -n "${DL_BACKUP_RSYNC:-}" ]; then rsync -a "$OUT" "$DL_BACKUP_RSYNC" && echo "copied off-site (rsync)"; fi
if [ -n "${DL_BACKUP_RCLONE:-}" ]; then rclone copy "$OUT" "$DL_BACKUP_RCLONE" && echo "copied off-site (rclone)"; fi
echo "$(date -Is) backup ok: $OUT ($(du -h "$OUT" | cut -f1))"
