#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/waqaarhussain/kids-control-hub.git"
REPO_DIR="/opt/kids-control-hub"

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer with sudo/root."
  exit 1
fi

echo
echo "=============================================="
echo " Kids Control Hub"
echo " GitHub Installer / Upgrader"
echo "=============================================="
echo

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y git ca-certificates curl

if [[ -d "$REPO_DIR/.git" ]]; then
  echo "Updating existing repository..."
  git -C "$REPO_DIR" fetch --prune origin
  git -C "$REPO_DIR" checkout main
  git -C "$REPO_DIR" reset --hard origin/main
else
  echo "Cloning Kids Control Hub..."
  rm -rf "$REPO_DIR"
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
fi

chmod +x "$REPO_DIR"/scripts/*.sh "$REPO_DIR"/scripts/update-live

if [[ -f /etc/kids-control.env && -f /etc/systemd/system/kids-control.service ]]; then
  echo
  echo "Existing Kids Control install detected."
  echo "Preserving database, login and environment settings."
  "$REPO_DIR/scripts/deploy-vps.sh"
else
  echo
  echo "Fresh install detected."
  "$REPO_DIR/scripts/bootstrap-vps.sh"
fi

ln -sf "$REPO_DIR/scripts/update-live" /usr/local/bin/update-live

echo
echo "=============================================="
echo " GitHub deployment complete"
echo "=============================================="
echo
echo "Future updates:"
echo "  update-live"
echo
