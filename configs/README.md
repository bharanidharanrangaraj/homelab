# configs/

Copies of real config files from the Pi, with private details replaced.

- **Domain names** are replaced with `example.com` / `example.net` names.
- **Port numbers** other than the standard web ports are replaced with placeholders such as `<api-port>`.
- **Usernames and tunnel IDs** are replaced with placeholders such as `user` and `<TUNNEL-ID>`.
- **No secrets.** No passwords, keys, certificates, `.env` files or tunnel credentials are included.
- **No client site configs.**

| Folder | On the Pi | What |
|---|---|---|
| [nginx/](nginx/) | `/etc/nginx/sites-available/` | IoT Studio: landing page and app (reverse proxy, security headers, CSP) |
| [apache/](apache/) | `/etc/apache2/` | Listen on localhost only, and the Licence Manager site |
| [cloudflared/](cloudflared/) | `/etc/cloudflared/` | Example tunnel config with ingress rules |
| [systemd/](systemd/) | `/etc/systemd/system/` | App and tunnel services, plus drop-ins |
| [mosquitto/](mosquitto/) | `/etc/mosquitto/` | MQTT broker: Dynamic Security, TLS, limits |
| [ssh/](ssh/) | `/etc/ssh/sshd_config.d/` | The SSH hardening drop-in |
| [fail2ban/](fail2ban/) | `/etc/fail2ban/jail.d/` | The sshd jail |
| [cron.d/](cron.d/) | `/etc/cron.d/` | Backup and demo-reset jobs |
| [apt/](apt/) | `/etc/apt/apt.conf.d/` | Automatic updates |
