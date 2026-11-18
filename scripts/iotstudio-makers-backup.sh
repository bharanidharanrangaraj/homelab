#!/usr/bin/env bash
set -euo pipefail
set -a; . /opt/iotstudio-makers/.env; set +a
OUT=/opt/iotstudio/backups/makers-$(date +%Y%m%d-%H%M%S).sql.gz
pg_dump --no-owner --no-privileges "$DL_DATABASE_URL" | gzip -9 > "$OUT"
ls -1t /opt/iotstudio/backups/makers-*.sql.gz | tail -n +15 | xargs -r rm -f
