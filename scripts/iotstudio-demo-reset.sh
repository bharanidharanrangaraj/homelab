#!/usr/bin/env bash
# No argument: puts the demo back to its starting state. "refresh": adds new readings so graphs and boards look live. Called by cron.
set -euo pipefail
set -a; . /opt/iotstudio-demo/.env; set +a
cd /opt/iotstudio/current/backend
if [ "${1:-}" = "refresh" ]; then CALL="demo.refresh()"; else CALL="demo.reset()"; fi
sudo -E -u iotstudio /opt/iotstudio/venv/bin/python -c "import demo; print($CALL)"
