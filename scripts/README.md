# scripts/

Scripts installed in `/usr/local/bin/` on the Pi. They come from IoT Studio's `deploy/` folder.
Paths and ports are sanitized.

| Script | What it does | How it runs |
|---|---|---|
| [iotstudio-backup.sh](iotstudio-backup.sh) | `pg_dump` + gzip of the IoT Studio database, plus the MQTT accounts file. Keeps 30. Optional extra copy with rsync or rclone. | cron, nightly, and before every deploy |
| [iotstudio-makers-backup.sh](iotstudio-makers-backup.sh) | Same for the Makers database. Keeps 14. | cron, nightly |
| [iotstudio-restore.sh](iotstudio-restore.sh) | Restores a backup: asks for confirmation, stops the app, recreates the database, loads the dump, starts the app. | by hand |
| [iotstudio-update.sh](iotstudio-update.sh) | Release-based deploy with migrations, health check and automatic rollback. | by hand, `sudo iotstudio-update` |
| [iotstudio-demo-reset.sh](iotstudio-demo-reset.sh) | Resets the public demo, or adds fresh readings so it looks live. | cron |
| [arduino-sandbox.sh](arduino-sandbox.sh) | Runs `arduino-cli` inside bubblewrap, so students' code compiles without network access or a view of the server. | called by the IoT Studio backend |

Settings and secrets come from each app's `.env` file, which is not in this repo.
