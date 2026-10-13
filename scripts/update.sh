#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() {
  printf '\n[DBA Pulse] %s\n' "$1"
}

die() {
  printf '\nERROR: %s\n' "$1" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || die 'git bulunamadı.'
command -v docker >/dev/null 2>&1 || die 'docker bulunamadı.'
[[ -f "$ROOT_DIR/docker-compose.phase2.yml" ]] || die 'docker-compose.phase2.yml bulunamadı.'
[[ -f "$ROOT_DIR/.env" ]] || die '.env bulunamadı. Önce scripts/setup.sh çalıştırılmalı.'
[[ -s "$ROOT_DIR/.secrets/dbapulse-admin-password" ]] || die '.secrets/dbapulse-admin-password bulunamadı veya boş. Update durduruldu; önce scripts/reset-admin-password.sh çalıştırın.'
mkdir -p "$ROOT_DIR/.runtime/settings"

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die 'Docker Compose bulunamadı.'
fi

docker info >/dev/null 2>&1 || die 'Docker daemon çalışmıyor veya erişilemiyor.'

log 'Uzak depodaki son kod alınıyor...'
git pull --ff-only origin main

log 'Ana yapı build edilip başlatılıyor...'
"${COMPOSE[@]}" -f "$ROOT_DIR/docker-compose.phase2.yml" up -d --build

collector_count=0
shopt -s nullglob
for override_file in "$ROOT_DIR"/.runtime/collectors/*/docker-compose.override.yml; do
  collector_dir="$(dirname "$override_file")"
  server_key="$(basename "$collector_dir")"
  project_name="dbapulse-$server_key"

  log "Collector güncelleniyor: $server_key"
  "${COMPOSE[@]}" \
    -f "$ROOT_DIR/docker-compose.phase2.yml" \
    -f "$override_file" \
    -p "$project_name" \
    up -d --build dbapulse-collector

  collector_count=$((collector_count + 1))
done
shopt -u nullglob

log "Güncelleme tamamlandı. $collector_count ek collector güncellendi."
log 'Ana servis durumu:'
"${COMPOSE[@]}" -f "$ROOT_DIR/docker-compose.phase2.yml" ps
