# Setup

These are the steps to rebuild this server as it is configured today, plus how I add and remove a
site. Commands are for Debian 13 / Raspberry Pi OS (64-bit). Names in `<angle brackets>` are placeholders.

## 1. Install the OS

1. Write **Raspberry Pi OS Lite (64-bit)** to the SSD with Raspberry Pi Imager. Set the user name and
   enable SSH in the Imager's settings. The Imager passes these to the Pi through cloud-init.
2. Plug the SSD in over USB and boot. The Pi 5 boots from USB without an SD card.
3. Update everything:
   ```sh
   sudo apt update && sudo apt full-upgrade -y
   ```

## 2. Admin access: Tailscale

```sh
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh          # join my tailnet and turn on Tailscale SSH
```

In the Tailscale admin console, the SSH rule for this machine uses the `check` action, so logins have
to be confirmed in the browser now and then.

## 3. SSH: keys only

On my PC:

```sh
ssh-keygen -t ed25519
cat ~/.ssh/id_ed25519.pub | ssh user@pi 'umask 077; mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'
ssh user@<pi-home-address> 'echo key login works'      # test a key login over the home network
```

Then on the Pi, add [configs/ssh/00-homelab-hardening.conf](../configs/ssh/00-homelab-hardening.conf)
to `/etc/ssh/sshd_config.d/`, then check it and reload:

```sh
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -Ei 'passwordauth|kbdinteractive|permitroot|pubkeyauth'   # the settings actually in use
```

Keep the current session open until a **new** login works.

## 4. Firewall, fail2ban, automatic updates

```sh
sudo apt install -y ufw fail2ban unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades       # writes /etc/apt/apt.conf.d/20auto-upgrades
```

The firewall pattern:

```sh
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow in on tailscale0                                     # first, so the Tailscale session survives
sudo ufw allow from <home-network> to any port <port> proto tcp     # only what home devices need
sudo ufw enable
```

Debian's fail2ban already enables the `sshd` jail ([configs/fail2ban/](../configs/fail2ban/)).

## 5. Web servers, PHP, databases, MQTT

```sh
sudo apt install -y nginx php8.4-fpm apache2 postgresql mariadb-server mosquitto
```

- **Apache** must not take port 80 from nginx. In `/etc/apache2/ports.conf` it listens only on a
  localhost port ([configs/apache/ports.conf](../configs/apache/ports.conf)).
- **PostgreSQL and MariaDB** listen on localhost by default on Debian. I keep it that way.
- **Mosquitto**: see [configs/mosquitto/iotstudio.conf](../configs/mosquitto/iotstudio.conf). Its header
  comment has the one-time Dynamic Security setup.

A database and user for a new app:

```sh
sudo -u postgres createuser --pwprompt appuser
sudo -u postgres createdb -O appuser appdb
```

## 6. Cloudflare Tunnel

Install `cloudflared` from Cloudflare's apt repository, so `apt` can update it:

```sh
sudo mkdir -p --mode=0755 /usr/share/keyrings
curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | sudo tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt update && sudo apt install -y cloudflared
```

Create a tunnel (once per tunnel):

```sh
cloudflared tunnel login                 # opens the browser and authorises my Cloudflare account
cloudflared tunnel create <name>         # creates the tunnel and its credentials JSON in ~/.cloudflared/
sudo mkdir -p /etc/cloudflared
sudo mv ~/.cloudflared/<TUNNEL-ID>.json /etc/cloudflared/ && sudo chmod 600 /etc/cloudflared/<TUNNEL-ID>.json
```

Write the config with its ingress rules ([example](../configs/cloudflared/config.example.yml)), add a
systemd unit ([example](../configs/systemd/cloudflared-iotstudio.service)), and start it:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-<name>
```

## Adding a new site

Say the new app is `newapp.example.com`, a Node.js app.

1. **Run the app as a systemd service** on a free localhost port, under its own user if possible.
   [configs/systemd/content-hub.service](../configs/systemd/content-hub.service) is a good template.
   The app must bind to `127.0.0.1`, not `0.0.0.0`.
   ```sh
   sudo systemctl daemon-reload && sudo systemctl enable --now newapp
   curl -I http://127.0.0.1:<app-port>/          # works on the Pi itself?
   ```
2. **Optional: put nginx in front** if it needs static files, headers or path routing. Add a `server`
   block with the site's `server_name`, `real_ip_header CF-Connecting-IP` and
   `proxy_pass http://127.0.0.1:<app-port>`. Then:
   ```sh
   sudo nginx -t && sudo systemctl reload nginx
   ```
3. **Add an ingress rule** to the tunnel config, above the final `http_status:404` rule. Check it
   before restarting:
   ```sh
   sudo cloudflared tunnel --config /etc/cloudflared/<name>.yml ingress validate
   sudo cloudflared tunnel --config /etc/cloudflared/<name>.yml ingress rule https://newapp.example.com
   ```
4. **Create the DNS record** that points the name at the tunnel:
   ```sh
   cloudflared tunnel route dns <name> newapp.example.com
   ```
5. **Restart the tunnel and test from outside:**
   ```sh
   sudo systemctl restart cloudflared-<name>
   curl -I https://newapp.example.com
   ```
6. **Add it to backups** if it stores data, and update [services.md](services.md).

No firewall change is needed: the request arrives through the tunnel.

## Removing a site

This is what I did for a retired client site. Its files and database were kept.

1. Back up the tunnel config, delete the site's ingress lines, then run `ingress validate` and
   `ingress rule https://<site>` (it should now match the 404 rule).
2. Restart that tunnel's service.
3. Turn the site off in the web server: `sudo a2dissite <site> && sudo apache2ctl configtest && sudo systemctl reload apache2`.
   With nginx, remove the link from `sites-enabled`, then run `nginx -t` and reload.
4. Check that `curl -I https://<site>` returns 404.
5. Delete the DNS record in the Cloudflare dashboard.
