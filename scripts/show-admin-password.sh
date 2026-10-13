#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRET_FILE="$ROOT_DIR/.secrets/dbapulse-admin-password"

if [[ ! -s "$SECRET_FILE" ]]; then
  printf 'ERROR: Admin secret dosyası bulunamadı veya boş: %s\n' "$SECRET_FILE" >&2
  exit 1
fi

printf 'Admin şifresi: '
cat "$SECRET_FILE"
printf '\n'
