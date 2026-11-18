# Troubleshooting

Real problems on this server and how I fixed them. Each fix was backed up first and tested afterwards.

## 1. SSH password login was on, even though sshd_config said no

**What I saw.** `/etc/ssh/sshd_config` had `PasswordAuthentication no`, but the setting sshd was
actually using was `yes`:

```
$ sudo sshd -T | grep passwordauthentication
passwordauthentication yes
```

There were also no SSH keys installed, so password login was the only way into OpenSSH.

**Why.** `sshd_config` starts with `Include /etc/ssh/sshd_config.d/*.conf`, and sshd keeps the
**first** value it reads for each setting. Raspberry Pi Imager uses cloud-init, which wrote
`/etc/ssh/sshd_config.d/50-cloud-init.conf` containing `PasswordAuthentication yes`. That file is
read before the main file's `no`, so it won.

**Fix.**

1. Made an ed25519 key on my PC, added it to `~/.ssh/authorized_keys`, and tested a key login.
2. Added `/etc/ssh/sshd_config.d/00-homelab-hardening.conf` ([copy](../configs/ssh/00-homelab-hardening.conf)).
   `00-` sorts before `50-`, so these settings win.
3. Ran `sudo sshd -t` (config check), then `sudo systemctl reload ssh`. Reload keeps open sessions.

**How I checked.** `sshd -T` now shows `passwordauthentication no`. From my PC, a login attempt with
every auth method turned off on my side shows what the server offers:

```
$ ssh -o PubkeyAuthentication=no -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no user@pi
user@pi: Permission denied (publickey).
```

Only `publickey` is offered now. Before the fix, the list included `password`.

**Lesson.** Don't trust the main config file. Check the setting the program actually uses (`sshd -T`, `nginx -T`).

## 2. The firewall allowed SSH from anywhere, including IPv6

**What I saw.** The only ufw rule was "allow OpenSSH from anywhere", for IPv4 and IPv6. Combined with
problem 1, that meant password-based SSH was open more widely than it needed to be. Some services were
also listening on all network interfaces instead of localhost.

**Fix.**

1. Rebuilt the rules: deny incoming by default, allow my Tailscale network, and allow only the few
   services that home-network devices need, from the home network.
2. Made the services that were listening on all interfaces listen on localhost. For example, a systemd
   drop-in sets `HOST=127.0.0.1` for one app ([copy](../configs/systemd/invio-frontend.service.d/listen-localhost.conf)).

**Not locking myself out.** Before changing anything, I scheduled an automatic undo with
`systemd-run --on-active=5min`, which restores the old rules. Then I logged in from a **new**
terminal and opened two sites. Only when both worked did I cancel the undo timer.

**How I checked.** From another machine I tried each port. The ones that should be closed were closed,
on IPv4 and IPv6, and the allowed ones still worked.

**Lesson.** Check IPv6 too, and always have an automatic way back when changing a firewall over SSH.

## 3. cloudflared was out of date, and two copies were installed

**What I saw.** Every tunnel logged `Your version ... is outdated`. There were two binaries:

- `/usr/bin/cloudflared`, from Cloudflare's apt repository;
- `/usr/local/bin/cloudflared`, copied in by hand.

Some tunnels used the hand-copied one, so an `apt upgrade` would never have updated them.
`--no-autoupdate` stops cloudflared updating itself, and unattended-upgrades only covers Debian's repositories.

**Fix.**

1. Ran `sudo apt install --only-upgrade cloudflared`.
2. Replaced the hand-copied binary with a symlink: `/usr/local/bin/cloudflared -> /usr/bin/cloudflared`.
3. Restarted the tunnels one at a time.

**How I checked.**

- `ps -o lstart,args -C cloudflared` shows every tunnel restarted on the new binary.
- Each tunnel's local metrics endpoint (`/ready`) returned 200.
- Every public site returned 200 or a redirect.

**Lesson.** One copy of each tool, installed from one place, so updates reach everything.

## 4. A retired client site was still public

**What I saw.** A client project that the client had rejected was still reachable on the internet,
through a tunnel ingress rule and an Apache site. Apache also had directory listing turned on
(`Options Indexes`). An unmaintained PHP app on the internet is a risk nobody is watching.

**Fix.**

1. Removed its ingress lines from the tunnel config.
2. Checked the config with `cloudflared tunnel ingress validate`. Then
   `cloudflared tunnel ingress rule https://<site>`, which showed the site now matches the 404 catch-all.
3. Restarted the tunnel.
4. Ran `a2dissite`, then `apache2ctl configtest`, then reloaded Apache.

The files and database were kept, in case they are needed later.

**How I checked.** The site returns 404, and the other sites on the same tunnel still work.

**Lesson.** When a project ends, take it offline. Unused sites still need patching, and nobody does it.
