#!/usr/bin/env bash
# IoT Studio — update to a new version, with automatic rollback.
#
#   sudo iotstudio-update [path-to-new-source]      (default: the checkout this script lives in)
#
# Takes a database backup, installs the new release next to the old one, applies migrations, switches over,
# restarts the services and checks /health. If anything fails it switches back to the previous release.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo $0"; exit 1; }
APP=/opt/iotstudio
SRC="${1:-$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)}"
[ -f "$SRC/backend/app.py" ] || { echo "Not an IoT Studio source folder: $SRC"; exit 1; }
STAMP=$(date +%Y%m%d-%H%M%S)
REL="$APP/releases/$STAMP"
PREV=$(readlink -f "$APP/current" || true)
say() { printf '\n== %s\n' "$*"; }

say "Backing up the database"
/usr/local/bin/iotstudio-backup

say "Installing release $STAMP"
mkdir -p "$REL"
rsync -a --exclude '.git' --exclude '.local' --exclude 'venv' --exclude '__pycache__' --exclude '.env' --exclude 'logs' "$SRC/" "$REL/"
"$APP/venv/bin/pip" install -q -r "$REL/backend/requirements.txt"
chown -R iotstudio:iotstudio "$REL"
cp "$REL"/deploy/systemd/iotstudio-*.service /etc/systemd/system/ && systemctl daemon-reload
NGINX_BAK=$(mktemp -d); cp -a /etc/nginx/sites-available/. "$NGINX_BAK"/ 2>/dev/null || true          # the old nginx files, to put back if the update fails
SERVER_NAME=$(grep -oP '(?<=^IOT_SERVER_NAME=")[^"]*' "$APP/.env" 2>/dev/null || true)
APP_NAME=$(grep -oP '(?<=^IOT_APP_NAME=")[^"]*' "$APP/.env" 2>/dev/null || true)          # set when the app has its own address (landing page apart)
ADMIN_NAME=$(grep -oP '(?<=^IOT_ADMIN_NAME=")[^"]*' "$APP/.env" 2>/dev/null || true)      # set when the master admin panel has its own address
IOT_SERVER_NAME="$SERVER_NAME" IOT_APP_NAME="$APP_NAME" IOT_ADMIN_NAME="$ADMIN_NAME" bash "$REL/deploy/render-nginx.sh" "$REL/deploy/nginx/iotstudio.conf" > /etc/nginx/sites-available/iotstudio
if [ -f /etc/nginx/sites-available/iotstudio-demo ]; then          # keep the demo site's nginx file in step, with the name it was installed for
  DEMO_HOST=$(grep -oP '(?<=server_name )[^;]+' /etc/nginx/sites-available/iotstudio-demo | head -1)
  sed -e "s#server_name demo.example.com;#server_name ${DEMO_HOST};#" -e "s#@LANDING_MAIN@#${DEMO_HOST#*.}#" "$REL/deploy/nginx/iotstudio-demo.conf" > /etc/nginx/sites-available/iotstudio-demo
fi
if [ -f /opt/iotstudio-makers/.env ]; then                         # keep the Makers cloud's nginx file in step too
  MK_NAME=$(grep -oP '(?<=^IOT_MAKERS_NAME=")[^"]*' /opt/iotstudio-makers/.env 2>/dev/null || true)
  MK_ADMIN=$(grep -oP '(?<=^IOT_ADMIN_NAME=")[^"]*' /opt/iotstudio-makers/.env 2>/dev/null || true)
  if [ -n "$MK_NAME" ] && [ -n "$MK_ADMIN" ]; then
    sed -e "s#@MAKERS_NAME@#$MK_NAME#g" -e "s#@ADMIN_NAME@#$MK_ADMIN#g" -e "s#@LANDING_MAIN@#${SERVER_NAME%% *}#g" \
        "$REL/deploy/nginx/iotstudio-makers.conf" > /etc/nginx/sites-available/iotstudio-makers
  fi
fi
install -m 755 "$REL/deploy/backup.sh" /usr/local/bin/iotstudio-backup
install -m 755 "$REL/deploy/restore.sh" /usr/local/bin/iotstudio-restore
install -m 755 "$REL/deploy/update.sh" /usr/local/bin/iotstudio-update
[ -f /usr/local/bin/arduino-sandbox ] && install -m 755 "$REL/deploy/arduino-sandbox.sh" /usr/local/bin/arduino-sandbox   # keep the compiler sandbox current

rollback() {
  echo "!! Update failed - rolling back to $PREV"
  [ -n "$PREV" ] && ln -sfn "$PREV" "$APP/current"
  cp -a "$NGINX_BAK"/. /etc/nginx/sites-available/ 2>/dev/null && nginx -t && systemctl reload nginx || true
  systemctl restart iotstudio-backend iotstudio-worker || true
  echo "The database backup taken before the update is in $APP/backups (restore with: iotstudio-restore <file>)"
  exit 1
}

say "Applying database migrations"
( cd "$REL/backend" && set -a && . "$APP/.env" && set +a && sudo -E -u iotstudio "$APP/venv/bin/python" manage.py migrate ) || rollback

say "Switching over"
ln -sfn "$REL" "$APP/current"
nginx -t && systemctl reload nginx || rollback
systemctl restart iotstudio-backend iotstudio-worker
systemctl is-enabled iotstudio-demo >/dev/null 2>&1 && systemctl restart iotstudio-demo || true       # the demo site runs the same release
systemctl is-enabled iotstudio-makers >/dev/null 2>&1 && systemctl restart iotstudio-makers iotstudio-makers-worker || true   # the Makers cloud too (it migrates its own database on start)
for i in $(seq 1 30); do curl -fs http://127.0.0.1:<api-port>/health >/dev/null && ok=1 && break; sleep 1; done
[ "${ok:-0}" = 1 ] || rollback
sleep 5
systemctl is-active --quiet iotstudio-worker || rollback

say "Cleaning up old releases (keeping 5)"
ls -1dt "$APP"/releases/* | tail -n +6 | xargs -r rm -rf
echo "Updated to $(cat "$REL/VERSION" 2>/dev/null || echo "$STAMP")."
