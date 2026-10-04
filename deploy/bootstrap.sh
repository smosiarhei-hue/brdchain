#!/usr/bin/env bash
#
# bootstrap.sh - install brdchain on a fresh Linux VPS and keep it running.
#
#   git clone https://github.com/smosiarhei-hue/brdchain && cd brdchain
#   BRD_USER='brd-customer-hl_XXXX-zone-isp_proxy1' BRD_PASS='...' \
#     sudo bash deploy/bootstrap.sh
#
# Everything sensitive arrives through the environment (or stdin) and lands in
# /etc/brdchain.env at mode 600. The only thing echoed back is the generated
# relay password, which you need for your client config.
#
# Idempotent: safe to re-run after editing /etc/brdchain.env.

set -euo pipefail

APP_DIR=/opt/brdchain
ENV_FILE=/etc/brdchain.env
UNIT=/etc/systemd/system/brdchain.service
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"

# ---------------------------------------------------------------- 1. python3
if ! command -v python3 >/dev/null 2>&1; then
  log "installing python3"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq python3
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q python3
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache python3
  else
    die "no supported package manager found, install python3 by hand"
  fi
fi
log "python3: $(python3 --version)"

# ---------------------------------------------------------------- 2. payload
log "installing to $APP_DIR"
install -d -m 755 "$APP_DIR"
install -m 644 "$SRC_DIR/brdchain.py" "$APP_DIR/brdchain.py"
install -m 644 "$SRC_DIR/brdchain.service" "$UNIT"

# ---------------------------------------------------------------- 3. config
if [ -f "$ENV_FILE" ]; then
  log "keeping existing $ENV_FILE (delete it first to regenerate)"
else
  BRD_USER="${BRD_USER:-}"
  BRD_PASS="${BRD_PASS:-}"
  if [ -z "$BRD_USER" ] || [ -z "$BRD_PASS" ]; then
    printf 'BRD_USER: '; read -r BRD_USER
    printf 'BRD_PASS: '; read -rs BRD_PASS; printf '\n'
  fi
  [ -n "$BRD_USER" ] && [ -n "$BRD_PASS" ] || die "BRD_USER and BRD_PASS are required"

  RELAY_USER="${RELAY_USER:-relay}"
  if [ -z "${RELAY_PASS:-}" ]; then
    RELAY_PASS="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
  fi

  umask 077
  cat > "$ENV_FILE" <<EOF
BRD_USER=$BRD_USER
BRD_PASS=$BRD_PASS
TARGET_HOST=${TARGET_HOST:-brd.superproxy.io}
TARGET_PORT=${TARGET_PORT:-44445}
FRONT_HOST=${FRONT_HOST:-}
FRONT_PORT=${FRONT_PORT:-}
FRONT_USER=${FRONT_USER:-}
FRONT_PASS=${FRONT_PASS:-}
LISTEN_HOST=0.0.0.0
LISTEN_PORT=1080
RELAY_USER=$RELAY_USER
RELAY_PASS=$RELAY_PASS
EOF
  chmod 600 "$ENV_FILE"
  log "wrote $ENV_FILE"
fi

# ---------------------------------------------------------------- 4. firewall
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  log "opening 1080/tcp in ufw"
  ufw allow 1080/tcp >/dev/null
fi
if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active --quiet firewalld; then
  log "opening 1080/tcp in firewalld"
  firewall-cmd --permanent --add-port=1080/tcp >/dev/null
  firewall-cmd --reload >/dev/null
fi

# ---------------------------------------------------------------- 5. service
log "enabling the service"
systemctl daemon-reload
systemctl enable brdchain >/dev/null
systemctl restart brdchain
sleep 2
if ! systemctl is-active --quiet brdchain; then
  journalctl -u brdchain -n 30 --no-pager
  die "service did not come up"
fi

PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"

# ---------------------------------------------------------------- 6. verify
log "verifying the chain from the host itself"
set -a; . "$ENV_FILE"; set +a
if python3 "$APP_DIR/brdchain.py" --check --listen-host 127.0.0.1 > /tmp/brdchain-check 2>&1; then
  cat /tmp/brdchain-check
  log "chain verified"
else
  cat /tmp/brdchain-check
  die "chain check failed, see the output above.
       ip_blacklisted means this host's exit IP is denied as well, so point
       FRONT_HOST/FRONT_PORT at a hop the zone does accept."
fi

printf '\n\033[1;32mready\033[0m  socks5://%s:1080\n' "$PUBLIC_IP"
printf 'client:   socks5://%s:%s@%s:1080\n' "$RELAY_USER" "$RELAY_PASS" "$PUBLIC_IP"
printf 'logs:     journalctl -u brdchain -f\n'
printf 'rotate:   change the Bright Data password, it has been in shell history\n'