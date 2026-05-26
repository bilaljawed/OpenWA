#!/bin/bash
set -e

COMPOSE="docker compose"
API_PORT="${API_PORT:-2785}"
DASHBOARD_PORT="${DASHBOARD_PORT:-2886}"

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

print_header() {
  echo -e "\n${BOLD}${BLUE}╔══════════════════════════════════════╗${NC}"
  echo -e "${BOLD}${BLUE}║         OpenWA Manager               ║${NC}"
  echo -e "${BOLD}${BLUE}╚══════════════════════════════════════╝${NC}\n"
}

info()    { echo -e "${CYAN}[INFO]${NC}  $1"; }
success() { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Helpers ──────────────────────────────────────────────────────────────────
require_docker() {
  docker info &>/dev/null || error "Docker no está corriendo. Inicia Docker Desktop primero."
}

get_profiles() {
  local profiles=()
  [[ "${DASHBOARD_ENABLED:-true}"  == "true" ]] && profiles+=("with-dashboard")
  [[ "${POSTGRES_BUILTIN:-false}"  == "true" ]] && profiles+=("postgres")
  [[ "${REDIS_BUILTIN:-false}"     == "true" ]] && profiles+=("redis")
  [[ "${MINIO_BUILTIN:-false}"     == "true" ]] && profiles+=("minio")
  echo "${profiles[@]}"
}

build_profile_flags() {
  local flags=""
  for p in $(get_profiles); do flags+="--profile $p "; done
  echo "$flags"
}

show_api_key() {
  local key_file="data/.api-key"
  if [[ -f "$key_file" ]]; then
    echo -e "${BOLD}  API Key:${NC}  $(cat "$key_file")"
  else
    # try reading from running container
    local key
    key=$(docker exec openwa-api cat /app/data/.api-key 2>/dev/null || echo "(inicia el servidor para verla)")
    echo -e "${BOLD}  API Key:${NC}  $key"
  fi
}

# ─── Commands ─────────────────────────────────────────────────────────────────

cmd_start() {
  require_docker
  local flags
  flags=$(build_profile_flags)

  info "Iniciando OpenWA..."
  # shellcheck disable=SC2086
  $COMPOSE $flags up -d --remove-orphans

  echo ""
  success "OpenWA corriendo"
  echo -e "  ${BOLD}API:${NC}       http://localhost:${API_PORT}/api/docs"
  echo -e "  ${BOLD}Dashboard:${NC} http://localhost:${DASHBOARD_PORT}"
  show_api_key
  echo ""
}

cmd_stop() {
  require_docker
  info "Deteniendo OpenWA..."
  $COMPOSE down
  success "Todos los contenedores detenidos"
}

cmd_restart() {
  cmd_stop
  echo ""
  cmd_start
}

cmd_build() {
  require_docker
  info "Reconstruyendo imágenes..."
  $COMPOSE build
  success "Build completado"
}

cmd_rebuild() {
  require_docker
  info "Reconstruyendo y reiniciando..."
  local flags
  flags=$(build_profile_flags)
  # shellcheck disable=SC2086
  $COMPOSE $flags up -d --build --remove-orphans
  success "Reconstruido y corriendo"
}

cmd_logs() {
  local service="${1:-}"
  if [[ -n "$service" ]]; then
    $COMPOSE logs -f "$service"
  else
    $COMPOSE logs -f
  fi
}

cmd_status() {
  require_docker
  echo -e "${BOLD}Contenedores:${NC}"
  $COMPOSE ps
  echo ""
  show_api_key
  echo ""
  echo -e "  ${BOLD}API:${NC}       http://localhost:${API_PORT}/api/docs"
  echo -e "  ${BOLD}Dashboard:${NC} http://localhost:${DASHBOARD_PORT}"
  echo ""
}

cmd_reset() {
  warn "Esto elimina contenedores y volúmenes (datos incluidos)."
  read -rp "¿Continuar? [s/N] " confirm
  [[ "$confirm" =~ ^[sS]$ ]] || { info "Cancelado"; exit 0; }
  $COMPOSE down -v
  success "Reset completo"
}

cmd_shell() {
  local service="${1:-openwa-api}"
  info "Abriendo shell en ${service}..."
  docker exec -it "$service" /bin/sh
}

cmd_key() {
  show_api_key
}

cmd_minimal() {
  require_docker
  info "Modo mínimo (solo API + SQLite, sin dashboard)..."
  $COMPOSE up -d --remove-orphans
  success "API corriendo en http://localhost:${API_PORT}"
  show_api_key
}

cmd_full() {
  require_docker
  info "Modo completo (API + Dashboard + Traefik)..."
  $COMPOSE --profile full up -d --remove-orphans
  success "OpenWA completo corriendo"
  echo -e "  ${BOLD}API:${NC}       http://localhost:${API_PORT}/api/docs"
  echo -e "  ${BOLD}Dashboard:${NC} http://localhost:${DASHBOARD_PORT}"
  show_api_key
}

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  print_header
  echo -e "${BOLD}Uso:${NC} ./openwa.sh <comando> [opciones]\n"
  echo -e "${BOLD}Comandos principales:${NC}"
  echo -e "  ${GREEN}start${NC}          Inicia según el .env (perfiles automáticos)"
  echo -e "  ${GREEN}stop${NC}           Detiene todos los contenedores"
  echo -e "  ${GREEN}restart${NC}        Detiene y vuelve a iniciar"
  echo -e "  ${GREEN}minimal${NC}        Solo API + SQLite (más rápido)"
  echo -e "  ${GREEN}full${NC}           API + Dashboard + Traefik"
  echo ""
  echo -e "${BOLD}Construcción:${NC}"
  echo -e "  ${GREEN}build${NC}          Reconstruye las imágenes"
  echo -e "  ${GREEN}rebuild${NC}        Reconstruye e inicia en un paso"
  echo ""
  echo -e "${BOLD}Diagnóstico:${NC}"
  echo -e "  ${GREEN}status${NC}         Estado de los contenedores + API key"
  echo -e "  ${GREEN}logs${NC} [servicio]  Logs en tiempo real (default: todos)"
  echo -e "  ${GREEN}shell${NC} [servicio] Shell interactivo (default: openwa-api)"
  echo -e "  ${GREEN}key${NC}            Muestra la API key"
  echo ""
  echo -e "${BOLD}Otros:${NC}"
  echo -e "  ${GREEN}reset${NC}          Elimina contenedores y volúmenes (⚠ borra datos)"
  echo ""
  echo -e "${BOLD}Ejemplos:${NC}"
  echo -e "  ./openwa.sh start"
  echo -e "  ./openwa.sh logs openwa-api"
  echo -e "  ./openwa.sh shell openwa-api"
  echo -e "  ./openwa.sh rebuild"
  echo ""
}

# ─── Router ───────────────────────────────────────────────────────────────────
cd "$(dirname "$0")"

# Load .env if exists
[[ -f .env ]] && set -a && source .env && set +a

case "${1:-}" in
  start)    cmd_start ;;
  stop)     cmd_stop ;;
  restart)  cmd_restart ;;
  build)    cmd_build ;;
  rebuild)  cmd_rebuild ;;
  logs)     cmd_logs "${2:-}" ;;
  status)   cmd_status ;;
  reset)    cmd_reset ;;
  shell)    cmd_shell "${2:-openwa-api}" ;;
  key)      cmd_key ;;
  minimal)  cmd_minimal ;;
  full)     cmd_full ;;
  *)        usage ;;
esac
