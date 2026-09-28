#!/usr/bin/env bash
set -Eeuo pipefail

# Adds a monitored SQL Server without changing the API, collector code or
# management schema. One Collector instance is created per source SQL Server.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=()
SERVER_KEY=""
SOURCE_CONNECTION="${DBAPULSE_NEW_SOURCE_CONNECTION:-}"
SOURCE_HOST=""
SOURCE_PORT="1433"
SOURCE_LOGIN="DBA_PULSE"
FORCE=false
DRY_RUN=false

log() { printf '\n[DBA Pulse] %s\n' "$1"; }
die() { printf '\nERROR: %s\n' "$1" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage:
  ./scripts/add-server.sh --name <collector-key> [options]

Options:
  --name <value>                Unique local key, for example sql02
  --host <value>                Source SQL Server hostname or IP
  --port <value>                Source SQL Server port (default: 1433)
  --login <value>               Source login (default: DBA_PULSE)
  --source-connection <value>   Full connection string; avoid shell history when possible
  --force                       Replace the generated local collector definition
  --dry-run                     Generate and validate the definition without starting Docker
  --help                        Show this help

Non-interactive use:
  DBAPULSE_NEW_SOURCE_CONNECTION='Server=...;Database=master;...' \
    ./scripts/add-server.sh --name sql02

The source login must already exist and have the permissions from:
  database/security/Grant_DBA_PULSE_Source_ReadOnly.sql

The script stores the generated collector definition under .runtime/.
That directory is ignored by Git and contains the source connection string.
EOF
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

select_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    die 'Docker Compose v2 not found.'
  fi
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
  [[ -n "$value" ]] || die 'Source password cannot be empty.'
  printf '%s' "$value"
}

yaml_single_quote() {
  local value="$1"
  value="${value//\'/\'\'}"
  printf "'%s'" "$value"
}

slugify() {
  local value="$1"
  value="$(printf '%s' "$value" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//')"
  [[ -n "$value" ]] || die 'Server key must contain at least one letter or number.'
  [[ "$value" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die 'Server key contains unsupported characters.'
  (( ${#value} <= 50 )) || die 'Server key must be 50 characters or shorter.'
  printf '%s' "$value"
}

build_source_connection() {
  local host="$1"
  local port="$2"
  local login="$3"
  local password="$4"
  local server_part="$host"
  [[ -n "$port" ]] && server_part="$host,$port"
  password="${password//\"/\"\"}"
  printf 'Server=%s;Database=master;User Id=%s;Password="%s";Encrypt=False;TrustServerCertificate=True;' \
    "$server_part" "$login" "$password"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ $# -ge 2 ]] || die '--name requires a value.'
      SERVER_KEY="$2"; shift 2 ;;
    --host)
      [[ $# -ge 2 ]] || die '--host requires a value.'
      SOURCE_HOST="$2"; shift 2 ;;
    --port)
      [[ $# -ge 2 ]] || die '--port requires a value.'
      SOURCE_PORT="$2"; shift 2 ;;
    --login)
      [[ $# -ge 2 ]] || die '--login requires a value.'
      SOURCE_LOGIN="$2"; shift 2 ;;
    --source-connection)
      [[ $# -ge 2 ]] || die '--source-connection requires a value.'
      SOURCE_CONNECTION="$2"; shift 2 ;;
    --force)
      FORCE=true; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --help|-h)
      usage; exit 0 ;;
    *)
      usage >&2; die "Unknown argument: $1" ;;
  esac
done

[[ -n "$SERVER_KEY" ]] || { usage >&2; die '--name is required.'; }
SERVER_KEY="$(slugify "$SERVER_KEY")"

require_command docker
select_compose
if [[ "$DRY_RUN" != true ]]; then
  docker info >/dev/null 2>&1 || die 'Docker daemon is not running or is not accessible.'
fi
[[ -f "$ROOT_DIR/docker-compose.phase2.yml" ]] || die 'docker-compose.phase2.yml not found.'
[[ -f "$ROOT_DIR/.env" ]] || die '.env not found. Run the normal DBA Pulse setup first.'

if [[ -z "$SOURCE_CONNECTION" ]]; then
  [[ -n "$SOURCE_HOST" ]] || SOURCE_HOST="$(read_required 'Source SQL Server host or IP')"
  SOURCE_PORT="${SOURCE_PORT:-1433}"
  [[ "$SOURCE_PORT" =~ ^[0-9]+$ ]] || die 'Source port must be numeric.'
  (( SOURCE_PORT >= 1 && SOURCE_PORT <= 65535 )) || die 'Source port must be between 1 and 65535.'
  password="$(read_secret "Password for source login [$SOURCE_LOGIN]")"
  SOURCE_CONNECTION="$(build_source_connection "$SOURCE_HOST" "$SOURCE_PORT" "$SOURCE_LOGIN" "$password")"
  unset password
fi

[[ "$SOURCE_CONNECTION" != *$'\n'* && "$SOURCE_CONNECTION" != *$'\r'* ]] || die 'Connection string cannot contain a newline.'

runtime_dir="$ROOT_DIR/.runtime/collectors/$SERVER_KEY"
override_file="$runtime_dir/docker-compose.override.yml"
container_name="dbapulse-collector-$SERVER_KEY"
project_name="dbapulse-$SERVER_KEY"

if [[ -e "$runtime_dir" && "$FORCE" != true ]]; then
  die "A collector definition already exists for '$SERVER_KEY'. Use --force to replace its local definition."
fi

mkdir -p "$runtime_dir"
chmod 700 "$ROOT_DIR/.runtime" "$ROOT_DIR/.runtime/collectors" "$runtime_dir"

quoted_source="$(yaml_single_quote "$SOURCE_CONNECTION")"
{
  printf '%s\n' 'services:'
  printf '  dbapulse-collector:\n'
  printf '    container_name: %s\n' "$container_name"
  printf '    restart: unless-stopped\n'
  printf '    environment:\n'
  printf '      DBAPULSE_SOURCE_CONNECTION: %s\n' "$quoted_source"
} > "$override_file"
chmod 600 "$override_file"
unset quoted_source

compose_args=(
  -f "$ROOT_DIR/docker-compose.phase2.yml"
  -f "$override_file"
  -p "$project_name"
)

log "Validating Compose definition for $SERVER_KEY..."
"${COMPOSE[@]}" "${compose_args[@]}" config >/dev/null || die 'Generated collector Compose definition is invalid.'

if [[ "$DRY_RUN" == true ]]; then
  printf '\nDry run completed. Generated definition: %s\n' "$override_file"
  exit 0
fi

log "Starting collector $container_name..."
"${COMPOSE[@]}" "${compose_args[@]}" up -d --build dbapulse-collector

running="$(docker inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
[[ "$running" == true ]] || die "Collector container did not start: $container_name"

cat <<EOF

Server onboarding started successfully.

Collector: $container_name
Project:   $project_name

The collector will discover the actual server name from server-info.sql and
sync it into DBA_PULSE.dbo.Servers on the first successful cycle.

Check logs:
  docker logs -f $container_name

Check the server list:
  GET /api/servers

Stop this collector:
  ${COMPOSE[*]} ${compose_args[*]} stop dbapulse-collector

The source permission script must be applied once on the new source SQL Server:
  database/security/Grant_DBA_PULSE_Source_ReadOnly.sql
EOF
