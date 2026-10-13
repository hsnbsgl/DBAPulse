#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

die() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || die 'docker bulunamadı.'
[[ -f "$ROOT_DIR/docker-compose.phase2.yml" ]] || die 'docker-compose.phase2.yml bulunamadı.'

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die 'Docker Compose bulunamadı.'
fi

read -r -s -p 'Yeni admin şifresi: ' password
printf '\n' >&2
read -r -s -p 'Yeni admin şifresi (tekrar): ' confirmation
printf '\n' >&2
[[ ${#password} -ge 8 ]] || die 'Admin şifresi en az 8 karakter olmalıdır.'
[[ "$password" == "$confirmation" ]] || die 'Şifreler eşleşmiyor.'

umask 077
mkdir -p "$ROOT_DIR/.secrets"
printf '%s' "$password" > "$ROOT_DIR/.secrets/dbapulse-admin-password"
unset password confirmation

"${COMPOSE[@]}" -f "$ROOT_DIR/docker-compose.phase2.yml" up -d --force-recreate dbapulse-api
printf '\nAdmin şifresi güncellendi.\n'
