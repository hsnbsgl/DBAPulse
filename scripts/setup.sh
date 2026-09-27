#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() { printf '\n[%s] %s\n' 'DBA Pulse' "$1"; }
die() { printf '\nHATA: %s\n' "$1" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die 'Docker bulunamadı.'
docker info >/dev/null 2>&1 || die 'Docker daemon çalışmıyor veya mevcut kullanıcı Docker kullanamıyor.'
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  die 'Docker Compose v2 bulunamadı.'
fi
command -v openssl >/dev/null 2>&1 || die 'OpenSSL bulunamadı. Red Hat üzerinde openssl paketini kurun.'

read_default() {
  local prompt="$1" default="$2" value
  read -r -p "$prompt [$default]: " value
  printf '%s' "${value:-$default}"
}
read_required() {
  local prompt="$1" value
  while true; do
    read -r -p "$prompt: " value
    [[ -n "$value" ]] && { printf '%s' "$value"; return; }
  done
}
read_secret() {
  local prompt="$1" value
  read -r -s -p "$prompt: " value
  printf '\n' >&2
  printf '%s' "$value"
}

sql_connection_value() {
  local value="$1"
  value="${value//\"/\"\"}"
  printf '"%s"' "$value"
}
dotenv_quote() {
  local value="$1"
  value="${value//\'/\\\'}"
  printf "'%s'" "$value"
}

ensure_certificate() {
  mkdir -p certs
  chmod 700 certs
  [[ -f certs/dbapulse.crt && -f certs/dbapulse.key ]] && return
  log 'Self-signed HTTPS sertifikası oluşturuluyor...'
  local config
  config="$(mktemp)"
  trap 'rm -f "$config"' RETURN
  printf '%s\n' \
    '[req]' \
    'distinguished_name = req_distinguished_name' \
    'x509_extensions = v3_req' \
    'prompt = no' \
    '[req_distinguished_name]' \
    'CN = localhost' \
    '[v3_req]' \
    'subjectAltName = DNS:localhost,IP:127.0.0.1' > "$config"
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout certs/dbapulse.key -out certs/dbapulse.crt -days 825 \
    -config "$config" -extensions v3_req >/dev/null 2>&1 \
    || die 'HTTPS sertifikası oluşturulamadı.'
  chmod 600 certs/dbapulse.key
  chmod 644 certs/dbapulse.crt
  rm -f "$config"
  trap - RETURN
}

ensure_ollama() {
  local model="$1" name='dbapulse-ollama'
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    docker start "$name" >/dev/null 2>&1 || true
  else
    docker run -d --name "$name" --restart unless-stopped ollama/ollama:latest >/dev/null \
      || die 'Ollama containerı başlatılamadı.'
  fi
  log "Local LLM indiriliyor: $model"
  if ! docker exec "$name" ollama pull "$model"; then
    read -r -p 'TLS hatası olabilir. --insecure ile tekrar denensin mi? (Y/N) [N]: ' retry
    if [[ "$retry" =~ ^[YyEe]$ ]]; then
      docker exec "$name" ollama pull --insecure "$model" \
        || die "Model indirilemedi: $model"
    else
      die "Model indirilemedi: $model"
    fi
  fi
}

log 'Red Hat Linux tek komut kurulum sihirbazı'
printf '%s\n' 'Kurulum Docker çalışan bu makineye yapılır. SQL Server uzak olabilir.'

sql_server="$(read_default 'SQL Server adresi veya hostname' 'localhost')"
sql_port="$(read_default 'SQL Server portu' '1433')"
sql_login="$(read_default 'SQL Server login kullanıcı adı' 'sa')"
sql_password="$(read_secret 'SQL Server login şifresi')"
[[ -n "$sql_password" ]] || die 'SQL Server şifresi boş olamaz.'

admin_user="$(read_default 'DBA Pulse admin kullanıcı adı' 'admin')"
admin_password="$(read_secret 'DBA Pulse admin şifresi')"
[[ ${#admin_password} -ge 8 ]] || die 'Admin şifresi en az 8 karakter olmalıdır.'

install_llm_answer="$(read_default 'Local LLM kurulsun mu? (Y/N)' 'N')"
install_llm=false
[[ "$install_llm_answer" =~ ^[YyEe]$ ]] && install_llm=true
llm_model='qwen2.5-coder:3b'
if [[ "$install_llm" == true ]]; then
  llm_model="$(read_default 'Local LLM modeli' "$llm_model")"
fi

web_https_port="$(read_default 'Web HTTPS host portu' '8443')"
[[ "$web_https_port" =~ ^[0-9]+$ ]] || die 'HTTPS portu sayısal olmalıdır.'
(( web_https_port >= 1 && web_https_port <= 65535 )) || die 'HTTPS portu 1-65535 arasında olmalıdır.'
server_part="$sql_server"
[[ -n "$sql_port" ]] && server_part="$sql_server,$sql_port"
quoted_password="$(sql_connection_value "$sql_password")"
source_connection="Server=$server_part;Database=master;User Id=$sql_login;Password=$quoted_password;Encrypt=False;TrustServerCertificate=True;"
management_connection="Server=$server_part;Database=DBA_PULSE;User Id=$sql_login;Password=$quoted_password;Encrypt=False;TrustServerCertificate=True;"

mkdir -p .secrets
chmod 700 .secrets
printf '%s' "$admin_password" > .secrets/dbapulse-admin-password
chmod 600 .secrets/dbapulse-admin-password
ensure_certificate

ai_provider='gemini'
ai_model='gemini-flash-latest'
ai_base_url='https://generativelanguage.googleapis.com/v1beta'
ai_protocol='gemini'
ai_api_key=''
if [[ "$install_llm" == true ]]; then
  ai_provider='onprem'
  ai_model="$llm_model"
  ai_base_url='http://dbapulse-ollama:11434/v1'
  ai_protocol='chat-completions'
  ai_api_key='ollama'
fi

log '.env oluşturuluyor...'
{
  printf 'DBAPULSE_SOURCE_CONNECTION=%s\n' "$(dotenv_quote "$source_connection")"
  printf 'DBAPULSE_MANAGEMENT_CONNECTION=%s\n' "$(dotenv_quote "$management_connection")"
  printf 'DBAPULSE_API_CONNECTION=%s\n' "$(dotenv_quote "$management_connection")"
  printf 'DBAPULSE_ADMIN_USERNAME=%s\n' "$(dotenv_quote "$admin_user")"
  printf 'DBAPULSE_DISPLAY_TIMEZONE=%s\n' "$(dotenv_quote 'Europe/Istanbul')"
  printf 'DBAPULSE_AI_PROVIDER=%s\n' "$(dotenv_quote "$ai_provider")"
  printf 'DBAPULSE_AI_MODEL=%s\n' "$(dotenv_quote "$ai_model")"
  printf 'DBAPULSE_AI_BASE_URL=%s\n' "$(dotenv_quote "$ai_base_url")"
  printf 'DBAPULSE_AI_PROTOCOL=%s\n' "$(dotenv_quote "$ai_protocol")"
  printf 'DBAPULSE_AI_API_KEY=%s\n' "$(dotenv_quote "$ai_api_key")"
  printf 'DBAPULSE_COLLECTION_INTERVAL_MINUTES=%s\n' "$(dotenv_quote '5')"
  printf 'DBAPULSE_WEB_HTTPS_PORT=%s\n' "$(dotenv_quote "$web_https_port")"
} > .env
chmod 600 .env

if [[ "$install_llm" == true ]]; then
  ensure_ollama "$llm_model"
fi

log 'Docker image build ve servis başlatma işlemi başlıyor...'
"${COMPOSE[@]}" -f docker-compose.phase2.yml up -d --build

if [[ "$install_llm" == true ]]; then
  network="$(docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' dbapulse-api | head -n 1)"
  [[ -n "$network" ]] || die 'DBA Pulse Docker network bulunamadı.'
  docker network connect "$network" dbapulse-ollama 2>/dev/null || true
fi

log 'Migration ve API health kontrolü bekleniyor...'
healthy=false
for _ in $(seq 1 45); do
  if curl -kfsS --max-time 5 https://127.0.0.1:${web_https_port}/api/health >/dev/null 2>&1; then
    healthy=true
    break
  fi
  sleep 2
done

if [[ "$healthy" != true ]]; then
  printf '%s\n' 'API health kontrolü zaman aşımına uğradı.' >&2
  "${COMPOSE[@]}" -f docker-compose.phase2.yml logs --tail=80 dbapulse-api dbapulse-collector >&2 || true
  exit 1
fi

printf '\nKurulum tamamlandı.\n'
printf 'Web:   https://localhost:${web_https_port}\n'
printf 'Admin: %s\n' "$admin_user"
printf 'AI:    %s' "$ai_provider"
[[ "$install_llm" == true ]] && printf ' / %s' "$llm_model"
printf "\nSQL ve admin secret bilgileri .env ve .secrets altında tutulur; bu dosyaları Git'e göndermeyin.\n"
