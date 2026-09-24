#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/opt/kids-control"
APP_USER="kidscontrol"
SERVICE="kids-control"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/deploy-vps.sh"
  exit 1
fi

if ! id "$APP_USER" >/dev/null 2>&1; then
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi

mkdir -p "$APP_DIR/data"

rm -rf "$APP_DIR/templates" "$APP_DIR/static"
rm -f "$APP_DIR/app.py" "$APP_DIR/requirements.txt"
cp -a "$ROOT_DIR/server/app.py" "$ROOT_DIR/server/requirements.txt" "$APP_DIR/"
cp -a "$ROOT_DIR/server/templates" "$ROOT_DIR/server/static" "$APP_DIR/"

python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip >/dev/null
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt" >/dev/null

chown -R "$APP_USER:$APP_USER" "$APP_DIR"
chmod 750 "$APP_DIR" "$APP_DIR/data"

if [[ ! -f /etc/kids-control.env ]]; then
  echo "Missing /etc/kids-control.env. Run the original bootstrap first."
  exit 1
fi

for line in   'PUBLIC_BASE_URL='   'APPLE_TEAM_ID='   'APPLE_KEY_ID='   'APPLE_BUNDLE_ID=com.kidscontrol.hub'   'APNS_KEY_PATH=/etc/kids-control/AuthKey.p8'   'APNS_ENV=production'
do
  key="${line%%=*}"
  grep -q "^${key}=" /etc/kids-control.env || echo "$line" >> /etc/kids-control.env
done

systemctl restart "$SERVICE"
systemctl is-active --quiet "$SERVICE"

echo "Kids Control updated."
echo "Health:"
curl -fsS http://127.0.0.1:8765/health || true
echo
