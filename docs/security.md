# Security

What is actually set up on the Pi.

## Logging in

| What | How it is set up |
|---|---|
| Main way in | **Tailscale SSH** over my private Tailscale network, in "check" mode (it asks me to confirm the login in the browser now and then) |
| Fallback | **OpenSSH**, keys only, from my home network only |
| Password login | **Off**: `PasswordAuthentication no`, `KbdInteractiveAuthentication no` |
| Root login | **Off**: `PermitRootLogin no` |

The SSH settings are in a drop-in file named `00-homelab-hardening.conf`
([configs/ssh/](../configs/ssh/00-homelab-hardening.conf)). The `00-` name matters: sshd keeps the
**first** value it reads for each setting, and it reads the `sshd_config.d/` files in name order.
[Troubleshooting](troubleshooting.md#1-ssh-password-login-was-on-even-though-sshd_config-said-no) explains why.

To check the settings sshd is actually using: `sudo sshd -T | grep -Ei 'passwordauth|permitroot|pubkeyauth'`.

## Firewall (ufw)

- **Default:** deny everything coming in, allow everything going out. This applies to IPv4 and IPv6.
- **Allowed in:** my private Tailscale network, and a few services that devices on my home network
  use (the SSH fallback and MQTT).
- **Websites need no open port.** Their traffic arrives through Cloudflare Tunnel, which connects out from the Pi.

## Brute-force protection

**fail2ban** watches OpenSSH logins (the `sshd` jail, reading the systemd journal) and bans repeated
failures with nftables ([configs/fail2ban/](../configs/fail2ban/)).

## Updates

**unattended-upgrades** installs updates every day from the Debian, Debian-Security and Raspberry Pi
repositories ([configs/apt/](../configs/apt/)). Software from other repositories is updated with
`apt` when a new version is out.

## Web server hardening (nginx)

From [configs/nginx/iotstudio.conf](../configs/nginx/iotstudio.conf):

- **Real visitor IPs.** `real_ip_header CF-Connecting-IP`, trusted only from the Pi itself (where cloudflared connects from).
- **HTTPS only.** Requests that reached Cloudflare as plain HTTP are redirected to HTTPS.
- **Security headers.** `X-Content-Type-Options`, `X-Frame-Options DENY`, `Referrer-Policy`, `Permissions-Policy`.
- **Content-Security-Policy.** A strict policy on the app pages: no inline scripts and no third-party code.
- **Search engines kept out.** App pages send `X-Robots-Tag: noindex` and a robots.txt that disallows everything.
- **Smaller exposure.** `server_tokens off` and small upload size limits. PHP sites block dotfiles (`.env`, `.git`).

## Keeping apps apart

- **Separate users.** IoT Studio and Content Hub run as their own service users, not as root.
- **systemd sandboxing.** `NoNewPrivileges`, `PrivateTmp`, `ProtectHome`, and `ProtectSystem=strict`
  (the whole filesystem is read-only except the listed paths). Content Hub also drops every capability
  and limits network address families.
- **Untrusted code in a sandbox.** IoT Studio compiles students' Arduino code on the server. It runs
  inside **bubblewrap** ([scripts/arduino-sandbox.sh](../scripts/arduino-sandbox.sh)):
  - no network for the compile step;
  - only the system libraries (read-only) and the Arduino folder are visible;
  - the app's `.env` cannot be read;
  - if bubblewrap is missing, it refuses to compile.
- **Separate client sites.** Each client site has its own Cloudflare tunnel, and one has its own PHP-FPM pool.

## MQTT

- **Login required.** `allow_anonymous false` on both brokers. The backend creates and removes device
  accounts through Mosquitto's Dynamic Security plugin, so no password file is edited by hand.
- **TLS available** for devices (TLS 1.2), with a server certificate from my own certificate authority.
- **Limits.** `message_size_limit`, `max_inflight_messages` and `max_queued_messages`, so a misbehaving board can't flood the Pi.

## Secrets

- App secrets live in `.env` files that systemd loads with `EnvironmentFile=`, readable only by the app's user.
- Tunnel credentials stay in `/etc/cloudflared/`.
- None of these are in this repo, and `.gitignore` blocks `.env`, `*.json`, `*.key`, `*.pem` and `*.crt`.
