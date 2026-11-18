# Services

Everything on the Pi runs as a **systemd service**: systemd starts it at boot, restarts it if it
crashes (`Restart=always` or `on-failure`), and collects its logs in the journal. Docker and PM2 are
not used. Examples of the unit files are in [configs/systemd/](../configs/systemd/).

## Web servers

| Unit | What it does |
|---|---|
| `nginx` | Reverse proxy and static files for IoT Studio, and the client PHP sites |
| `apache2` | Licence Manager (PHP), on localhost only |
| `php8.4-fpm` | PHP for a client site (the shared pool) |
| a separate PHP-FPM unit | A PHP-FPM pool just for one client site, with its own config and log |

## Apps

All of these listen on localhost only.

| Unit | What it does | Runs as |
|---|---|---|
| `iotstudio-backend` | IoT Studio API: Flask on gunicorn, 3 workers × 2 threads | its own service user |
| `iotstudio-worker` | IoT Studio worker: MQTT ingest, alerts, automations, email, nightly maintenance | its own service user |
| demo API | The same code with its own database, for the public demo | its own service user |
| Makers API and worker | The Makers cloud: its own API, worker, database and MQTT broker | its own service user |
| `content-hub` | Content Hub (Node.js) | its own service user |
| `invio-frontend`, `invio-backend` | Invio: SvelteKit on Bun, API on Deno | my user |
| blog | IoT Studio blog (Node.js) | my user |

The IoT Studio units load their settings from an `EnvironmentFile` (an `.env` file readable only by
the app) and use systemd hardening: `NoNewPrivileges`, `PrivateTmp`, `ProtectHome`, and
`ProtectSystem=strict` with a short `ReadWritePaths` list. `content-hub` goes further: no
capabilities, `RestrictAddressFamilies`, `ProtectKernel*`, `UMask=0077` and more. See
[configs/systemd/content-hub.service](../configs/systemd/content-hub.service).

## Other services

| Unit | What it does |
|---|---|
| `mosquitto` + a second Mosquitto unit | The two MQTT brokers (IoT Studio and Makers) |
| `cloudflared-*` | One Cloudflare tunnel each for my sites and for each client site |
| `postgresql@17-main` | PostgreSQL: IoT Studio's databases (main, demo, Makers) |
| `mariadb` | MariaDB: the PHP sites |
| `ssh`, `tailscaled`, `ufw`, `fail2ban`, `unattended-upgrades`, `chrony`, `cron` | System services |

All tunnels use one `cloudflared` binary, installed from Cloudflare's apt repository.

## Cron jobs

Files in `/etc/cron.d/` ([configs/cron.d/](../configs/cron.d/)). All run as root and write to log
files under `/var/log/`.

| When | Job |
|---|---|
| 02:30 every day | `iotstudio-backup`: back up the IoT Studio database and MQTT accounts |
| 02:45 every day | `iotstudio-makers-backup`: back up the Makers database |
| 03:30 every day | `iotstudio-demo-reset`: put the demo site back to its starting state |
| every 10 minutes | `iotstudio-demo-reset refresh`: add new readings so the demo looks live |

Debian's own systemd timers handle package updates (`apt-daily`, `apt-daily-upgrade`), `logrotate`,
`fstrim` and similar housekeeping.

## Backups

| What | When | Kept |
|---|---|---|
| IoT Studio database (`pg_dump`, gzip) | every night, and before every deploy | newest 30 |
| MQTT accounts (the Dynamic Security JSON file) | every night | newest 30 |
| Makers database | every night | newest 14 |

Backup files are owned by the app's service user, with mode 600. To restore,
`sudo iotstudio-restore <file>`:

1. asks you to type `YES`,
2. stops the app,
3. recreates the database and loads the backup,
4. starts the app again.

See [scripts/iotstudio-restore.sh](../scripts/iotstudio-restore.sh).

## Deploys

IoT Studio uses `sudo iotstudio-update` ([scripts/iotstudio-update.sh](../scripts/iotstudio-update.sh)). It:

1. backs up the database,
2. copies the new code into `releases/<timestamp>` and installs Python packages,
3. updates the systemd units and nginx files from the release,
4. runs database migrations,
5. points the `current` symlink at the new release, then reloads nginx and restarts the services,
6. checks the API's `/health` endpoint for up to 30 seconds and checks that the worker is running,
7. if any step fails, it points the symlink back at the previous release and restores the old nginx files,
8. keeps the newest 5 releases.

The other apps are updated by hand.

## Everyday commands

```sh
systemctl status nginx                      # is it running? last log lines
sudo systemctl restart iotstudio-backend    # restart one app
journalctl -u iotstudio-backend -f          # follow an app's log
systemctl list-timers                       # what runs on a schedule
sudo ss -tlnp                               # what listens where
sudo ufw status verbose                     # firewall rules
```
