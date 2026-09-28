#!/usr/bin/env bash
set -Eeuo pipefail

# Lab-only update helper for the AI/LLM certificate validation override.
# This intentionally rebuilds only the API container.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

log() { printf '\n[DBA Pulse] %s\n' "$1"; }
die() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die 'Docker bulunamadı.'
[[ -f "$ROOT_DIR/.env" ]] || die '.env bulunamadı. Önce DBA Pulse kurulumunu tamamlayın.'
[[ -f "$ROOT_DIR/docker-compose.phase2.yml" ]] || die 'docker-compose.phase2.yml bulunamadı.'

if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die 'Docker Compose bulunamadı.'
fi

docker info >/dev/null 2>&1 || die 'Docker daemon çalışmıyor.'

tmp_env="$(mktemp "$ROOT_DIR/.env.update.XXXXXX")"
cleanup() { rm -f "$tmp_env"; }
trap cleanup EXIT

log 'Lab AI sertifika doğrulama ayarı etkinleştiriliyor...'
awk '
  BEGIN { found = 0 }
  /^[[:space:]]*DBAPULSE_AI_ALLOW_INVALID_CERTIFICATE[[:space:]]*=/ {
    if (!found) print "DBAPULSE_AI_ALLOW_INVALID_CERTIFICATE=true"
    found = 1
    next
  }
  { print }
  END {
    if (!found) print "DBAPULSE_AI_ALLOW_INVALID_CERTIFICATE=true"
  }
' "$ROOT_DIR/.env" > "$tmp_env"
chmod 600 "$tmp_env"
mv "$tmp_env" "$ROOT_DIR/.env"
trap - EXIT

log 'dbapulse-api image build ve container recreate işlemi başlıyor...'
"${COMPOSE[@]}" -f "$ROOT_DIR/docker-compose.phase2.yml" up -d --build --force-recreate dbapulse-api

running="$(docker inspect -f '{{.State.Running}}' dbapulse-api 2>/dev/null || true)"
[[ "$running" == true ]] || die 'dbapulse-api çalışır durumda değil.'

cat <<'EOF'

Güncelleme tamamlandı.

DBAPULSE_AI_ALLOW_INVALID_CERTIFICATE=true

Bu ayar yalnızca AI/LLM bağlantısında geçersiz sertifikalara izin verir.
Production ortamında kullanmayın.

Log kontrolü:
  docker logs --tail 100 dbapulse-api
EOF
