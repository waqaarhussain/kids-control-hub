#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="/opt/kids-control"
APP_USER="kidscontrol"
PORT="8765"

read -rp "Domain (blank for IP while testing): " DOMAIN </dev/tty
read -rp "Admin username [Waqaar]: " ADMIN_USER </dev/tty
ADMIN_USER="${ADMIN_USER:-Waqaar}"
read -rsp "Admin password (blank = generate): " ADMIN_PASSWORD </dev/tty
echo
if [[ -z "$ADMIN_PASSWORD" ]]; then ADMIN_PASSWORD="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9@#%=+' | head -c 20)"; fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip nginx curl openssl
if [[ -n "$DOMAIN" ]]; then apt-get install -y certbot python3-certbot-nginx; fi

id "$APP_USER" >/dev/null 2>&1 || useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$APP_USER"
mkdir -p "$APP_DIR/data"
cp -a "$ROOT_DIR/server/app.py" "$ROOT_DIR/server/requirements.txt" "$APP_DIR/"
cp -a "$ROOT_DIR/server/templates" "$ROOT_DIR/server/static" "$APP_DIR/"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip >/dev/null
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt" >/dev/null

PASSWORD_HASH="$(ADMIN_PASSWORD="$ADMIN_PASSWORD" "$APP_DIR/venv/bin/python" - <<'PY'
import os
from werkzeug.security import generate_password_hash
print(generate_password_hash(os.environ['ADMIN_PASSWORD']))
PY
)"
SECRET_KEY="$(openssl rand -hex 48)"

PUBLIC_BASE_URL=""
if [[ -n "$DOMAIN" ]]; then PUBLIC_BASE_URL="https://$DOMAIN"; fi
cat > /etc/kids-control.env <<EOF
ADMIN_USER=$ADMIN_USER
ADMIN_PASSWORD_HASH=$PASSWORD_HASH
SECRET_KEY=$SECRET_KEY
SECURE_COOKIE=0
PUBLIC_BASE_URL=$PUBLIC_BASE_URL
APPLE_TEAM_ID=
APPLE_KEY_ID=
APPLE_BUNDLE_ID=com.kidscontrol.hub
APNS_KEY_PATH=/etc/kids-control/AuthKey.p8
APNS_ENV=production
EOF
chmod 600 /etc/kids-control.env
chown -R "$APP_USER:$APP_USER" "$APP_DIR"

cat > /etc/systemd/system/kids-control.service <<EOF
[Unit]
Description=Kids Control Hub
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR
EnvironmentFile=/etc/kids-control.env
ExecStart=$APP_DIR/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:$PORT --timeout 30 app:app
Restart=always
RestartSec=3
PrivateTmp=true
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now kids-control

SERVER_NAME="_"; [[ -n "$DOMAIN" ]] && SERVER_NAME="$DOMAIN"
cat > /etc/nginx/sites-available/kids-control <<EOF
server {
  listen 80;
  listen [::]:80;
  server_name $SERVER_NAME;
  location / {
    proxy_pass http://127.0.0.1:$PORT;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/kids-control /etc/nginx/sites-enabled/kids-control
nginx -t
systemctl restart nginx

if [[ -n "$DOMAIN" ]]; then
  read -rp "Email for Let's Encrypt: " CERT_EMAIL </dev/tty
  certbot --nginx --non-interactive --agree-tos --redirect -m "$CERT_EMAIL" -d "$DOMAIN"
  sed -i 's/^SECURE_COOKIE=.*/SECURE_COOKIE=1/' /etc/kids-control.env
  systemctl restart kids-control
fi

IP="$(curl -4 -fsS https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
URL="http://$IP"; [[ -n "$DOMAIN" ]] && URL="https://$DOMAIN"
echo
printf 'Kids Control ready: %s\nUsername: %s\nPassword: %s\n' "$URL" "$ADMIN_USER" "$ADMIN_PASSWORD"
