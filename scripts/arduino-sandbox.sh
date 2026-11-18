#!/usr/bin/env bash
# Run arduino-cli inside a locked-down sandbox (bubblewrap).
#
# Students' code is compiled on the server. Without this wrapper arduino-cli (and the gcc it runs) can see the whole
# machine: the app's secrets in /opt/iotstudio/.env, the other websites on the box, and the network. This wrapper runs
# the compiler with NO view of anything except the system libraries (read-only) and /opt/arduino (its cores, libraries
# and the scratch build folder). It cannot read /opt/iotstudio/.env.
#
#   * "compile" (building a student's code -- the untrusted step) also gets NO network.
#   * "core" / "lib" / everything else keeps network so the administrator can still install boards and libraries;
#     those commands run only on an administrator's request and do not build student code.
#
# The backend calls this instead of arduino-cli when DL_ARDUINO_CLI points here (install-arduino.sh sets that up).
# It must stay a thin wrapper: it forwards every argument to the real arduino-cli unchanged.
set -euo pipefail

ARD="${DL_ARDUINO_HOME:-/opt/arduino}"                 # cores, libraries and the scratch build folder all live under here
REAL="${DL_ARDUINO_CLI_REAL:-/usr/local/bin/arduino-cli}"

# No bwrap (e.g. an old distro)? Fail closed: better to tell the student "building is unavailable" than to compile
# their code with full access to the server. Install it with: sudo apt-get install -y bubblewrap
if ! command -v bwrap >/dev/null 2>&1; then
  echo "arduino-sandbox: bubblewrap (bwrap) is not installed; refusing to compile without isolation." >&2
  echo "Install it with: sudo apt-get install -y bubblewrap" >&2
  exit 70
fi

# Building student code gets no network; administrator commands (core/lib install) keep it.
if [ "${1:-}" = "compile" ]; then
  NS=(--unshare-all)
else
  NS=(--unshare-user --unshare-ipc --unshare-pid --unshare-uts)
fi

# bind a path read-only if it exists (an "if", not "[ ] &&": under set -e a missing path, like /lib64 on a Raspberry Pi
# or /etc/pki on Debian, would otherwise end the script silently with status 1)
ro() { if [ -e "$1" ]; then RO+=(--ro-bind "$1" "$1"); fi; }
RO=()
ro /usr; ro /bin; ro /sbin; ro /lib; ro /lib64
# just the few /etc files the toolchain and (for downloads) TLS need -- never the whole of /etc, so other services'
# configuration on the same machine stays out of reach.
for f in /etc/alternatives /etc/ld.so.cache /etc/ld.so.conf /etc/ld.so.conf.d \
         /etc/passwd /etc/group /etc/nsswitch.conf /etc/resolv.conf /etc/hosts \
         /etc/ssl /etc/ca-certificates /etc/ca-certificates.conf /etc/pki; do
  ro "$f"
done

exec bwrap \
  "${NS[@]}" \
  --die-with-parent \
  --new-session \
  --clearenv \
  --setenv PATH /usr/local/bin:/usr/bin:/bin \
  --setenv HOME "$ARD" \
  --setenv ARDUINO_DIRECTORIES_DATA "$ARD/data" \
  --setenv ARDUINO_DIRECTORIES_USER "$ARD/user" \
  --setenv LANG "${LANG:-C.UTF-8}" \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  "${RO[@]}" \
  --bind "$ARD" "$ARD" \
  --chdir "$ARD" \
  "$REAL" "$@"
