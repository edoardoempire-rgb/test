#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Esegui questo script come root." >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
  systemctl enable --now docker
fi

if [ ! -f .env ]; then
  cp .env.example .env
fi

docker compose up -d --build
docker compose ps

echo
echo "Wallet Skins avviato. Il reverse proxy HTTPS deve inoltrare a 127.0.0.1:8787:"
echo "https://wallet.82-165-176-79.sslip.io"
