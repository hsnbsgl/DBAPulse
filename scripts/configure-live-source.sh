#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

die() {
  echo "Hata: $*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || die "jq gerekli. Debian/Ubuntu: sudo apt-get install -y jq"

[[ -f "$ENV_FILE" ]] || die "$ENV_FILE bulunamadı. Önce .env dosyasını oluşturun."

server_id="${1:-${DBAPULSE_LIVE_SERVER_ID:-}}"
connection_string="${2:-${DBAPULSE_SOURCE_CONNECTION:-}}"

[[ "$server_id" =~ ^[0-9]+$ ]] || die "Kullanım: $0 <server-id> [connection-string]"

if [[ -z "${2:-}" ]]; then
  if source_line="$(sed -n 's/^DBAPULSE_SOURCE_CONNECTION=//p' "$ENV_FILE" | head -n 1)" && [[ -n "$source_line" ]]; then
    connection_string="$source_line"
  fi
fi
[[ -n "$connection_string" ]] || die "DBAPULSE_SOURCE_CONNECTION .env içinde bulunamadı."

existing="{}"
if live_line="$(sed -n 's/^DBAPULSE_LIVE_SOURCE_CONNECTIONS=//p' "$ENV_FILE" | head -n 1)"; then
  if [[ -n "$live_line" ]]; then
    existing="$live_line"
  fi
fi

if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$existing"; then
  echo "Uyarı: mevcut DBAPULSE_LIVE_SOURCE_CONNECTIONS geçersiz; yedeklenip yeniden oluşturulacak." >&2
  existing="{}"
fi
updated="$(jq -c --arg id "$server_id" --arg connection "$connection_string" '.[$id] = $connection' <<<"$existing")"

backup_file="$ENV_FILE.bak.$(date +%Y%m%d%H%M%S)"
cp "$ENV_FILE" "$backup_file"
chmod 600 "$backup_file" 2>/dev/null || true

tmp_file="$(mktemp "$ROOT_DIR/.env.tmp.XXXXXX")"
replacement_file="$(mktemp "$ROOT_DIR/.env.live-source.tmp.XXXXXX")"
printf 'DBAPULSE_LIVE_SOURCE_CONNECTIONS=%s\n' "$updated" >"$replacement_file"
cleanup() { rm -f "$tmp_file" "$replacement_file"; }
trap cleanup EXIT

if grep -q '^DBAPULSE_LIVE_SOURCE_CONNECTIONS=' "$ENV_FILE"; then
  awk -v replacement_file="$replacement_file" '
    BEGIN {
      getline replacement < replacement_file
      close(replacement_file)
      replaced = 0
    }
    /^DBAPULSE_LIVE_SOURCE_CONNECTIONS=/ {
      print replacement
      replaced = 1
      next
    }
    { print }
    END {
      if (!replaced) print replacement
    }
  ' "$ENV_FILE" >"$tmp_file"
else
  cat "$ENV_FILE" >"$tmp_file"
  printf '\n' >>"$tmp_file"
  cat "$replacement_file" >>"$tmp_file"
fi

chmod --reference="$ENV_FILE" "$tmp_file" 2>/dev/null || chmod 600 "$tmp_file"
mv "$tmp_file" "$ENV_FILE"
trap - EXIT

echo "Server $server_id için live source bağlantısı kaydedildi."
echo ".env yedeği: $backup_file"
echo
echo "API container'ını yeniden oluşturun:"
echo "  docker compose -f docker-compose.phase2.yml up -d --force-recreate dbapulse-api"
