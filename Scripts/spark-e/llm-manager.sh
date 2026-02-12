#!/usr/bin/env bash
set -euo pipefail

# Purpose:  Local LLM Environment Manager for DGX Spark
#  Status:  working
#   Notes:  Manages Ollama, vLLM, or LMStudio (one engine at a time) plus OpenWebUI.
#           Replaces the former start_openwebui.sh script.

###############################################################################
# Constants & paths
###############################################################################
CONFIG_DIR="${HOME}/.config/llm-manager"
CONFIG_FILE="${CONFIG_DIR}/config"
ACTIVE_FILE="${CONFIG_DIR}/active"
ENGINES=("ollama" "vllm" "lmstudio")

CONTAINER_OLLAMA="llm-ollama"
CONTAINER_VLLM="llm-vllm"
CONTAINER_WEBUI="open-webui"

###############################################################################
# Default configuration
###############################################################################
declare -A DEFAULTS=(
  [OLLAMA_PORT]=11434
  [VLLM_PORT]=8000
  [LMSTUDIO_PORT]=1234
  [WEBUI_PORT]=12000
  [OLLAMA_IMAGE]="ollama/ollama"
  [VLLM_IMAGE]="vllm/vllm-openai"
  [WEBUI_IMAGE]="ghcr.io/open-webui/open-webui:main"
  [VLLM_MODEL]="meta-llama/Llama-3.1-8B-Instruct"
  [VLLM_GPU_MEMORY_UTIL]=0.9
  [OLLAMA_VOLUME]="llm-manager-ollama"
  [WEBUI_VOLUME]="llm-manager-webui"
)

###############################################################################
# Helpers
###############################################################################
die()  { echo "Error: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "Warning: $*" >&2; }

usage() {
  cat <<'EOF'
Usage: llm-manager.sh <command> [engine] [options]

Commands:
  start <engine>       Start an engine (ollama|vllm|lmstudio) + OpenWebUI
  stop [engine|all]    Stop engine and/or OpenWebUI
  restart <engine>     Stop then start
  status               Show what's running, ports, GPU usage
  update [engine|all]  Pull latest Docker images / update native installs
  logs <engine|webui>  Tail logs for a service
  models list          List models on current engine
  models pull <name>   Pull/download a model
  models rm <name>     Remove a model
  config show          Show current configuration
  config set <k> <v>   Set a config value
  config reset         Reset to defaults
EOF
  exit "${1:-0}"
}

###############################################################################
# Configuration management
###############################################################################
ensure_config_dir() {
  mkdir -p "${CONFIG_DIR}"
  [[ -f "${CONFIG_FILE}" ]] || write_defaults
}

write_defaults() {
  : > "${CONFIG_FILE}"
  for key in "${!DEFAULTS[@]}"; do
    echo "${key}=${DEFAULTS[$key]}" >> "${CONFIG_FILE}"
  done
  sort -o "${CONFIG_FILE}" "${CONFIG_FILE}"
}

load_config() {
  ensure_config_dir
  # Start with defaults, then overlay persisted values
  for key in "${!DEFAULTS[@]}"; do
    declare -g "$key=${DEFAULTS[$key]}"
  done
  while IFS='=' read -r key value; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    declare -g "$key=$value"
  done < "${CONFIG_FILE}"
}

config_show() {
  load_config
  info "Configuration (${CONFIG_FILE}):"
  sort "${CONFIG_FILE}"
}

config_set() {
  local key="${1:-}" value="${2:-}"
  [[ -z "${key}" || -z "${value}" ]] && die "Usage: config set <KEY> <VALUE>"
  load_config
  if grep -q "^${key}=" "${CONFIG_FILE}" 2>/dev/null; then
    sed -i'' -e "s|^${key}=.*|${key}=${value}|" "${CONFIG_FILE}"
  else
    echo "${key}=${value}" >> "${CONFIG_FILE}"
  fi
  info "Set ${key}=${value}"
}

config_reset() {
  write_defaults
  info "Configuration reset to defaults."
}

###############################################################################
# State helpers
###############################################################################
set_active_engine() {
  echo "$1" > "${ACTIVE_FILE}"
}

clear_active_engine() {
  rm -f "${ACTIVE_FILE}"
}

get_active_engine() {
  [[ -f "${ACTIVE_FILE}" ]] && cat "${ACTIVE_FILE}" || true
}

container_running() {
  docker ps -q --filter "name=^${1}$" --filter "status=running" 2>/dev/null | grep -q .
}

container_exists() {
  docker ps -aq --filter "name=^${1}$" 2>/dev/null | grep -q .
}

validate_engine() {
  local e="$1"
  for valid in "${ENGINES[@]}"; do
    [[ "${e}" == "${valid}" ]] && return 0
  done
  die "Unknown engine '${e}'. Valid engines: ${ENGINES[*]}"
}

engine_container_name() {
  case "$1" in
    ollama)   echo "${CONTAINER_OLLAMA}" ;;
    vllm)     echo "${CONTAINER_VLLM}" ;;
    lmstudio) echo "" ;;  # native process
  esac
}

engine_port() {
  case "$1" in
    ollama)   echo "${OLLAMA_PORT}" ;;
    vllm)     echo "${VLLM_PORT}" ;;
    lmstudio) echo "${LMSTUDIO_PORT}" ;;
  esac
}

engine_api_base() {
  local port
  port=$(engine_port "$1")
  case "$1" in
    ollama)   echo "http://host.docker.internal:${port}/v1" ;;
    vllm)     echo "http://host.docker.internal:${port}/v1" ;;
    lmstudio) echo "http://host.docker.internal:${port}/v1" ;;
  esac
}

###############################################################################
# Docker prerequisite check
###############################################################################
require_docker() {
  docker info >/dev/null 2>&1 || die "Docker daemon not reachable."
}

###############################################################################
# Stop helpers
###############################################################################
stop_container() {
  local name="$1"
  if container_running "${name}"; then
    info "Stopping ${name}..."
    docker stop "${name}" >/dev/null 2>&1 || true
  fi
  if container_exists "${name}"; then
    docker rm "${name}" >/dev/null 2>&1 || true
  fi
}

stop_engine() {
  local engine="$1"
  case "${engine}" in
    ollama) stop_container "${CONTAINER_OLLAMA}" ;;
    vllm)   stop_container "${CONTAINER_VLLM}" ;;
    lmstudio)
      if pgrep -f "lmstudio|lms server" >/dev/null 2>&1; then
        info "Stopping LMStudio server..."
        if command -v lms >/dev/null 2>&1; then
          lms server stop 2>/dev/null || true
        else
          pkill -f "lmstudio|lms server" 2>/dev/null || true
        fi
      fi
      ;;
  esac
}

stop_all_engines() {
  for e in "${ENGINES[@]}"; do
    stop_engine "$e"
  done
  clear_active_engine
}

stop_webui() {
  stop_container "${CONTAINER_WEBUI}"
}

###############################################################################
# Start helpers
###############################################################################
start_engine_ollama() {
  require_docker
  info "Starting Ollama engine..."
  docker run -d \
    --name "${CONTAINER_OLLAMA}" \
    --gpus=all --runtime=nvidia \
    -p "${OLLAMA_PORT}:11434" \
    -v "${OLLAMA_VOLUME}:/root/.ollama" \
    -e OLLAMA_HOST="0.0.0.0:11434" \
    "${OLLAMA_IMAGE}" >/dev/null
  info "Ollama running on port ${OLLAMA_PORT}."
}

start_engine_vllm() {
  require_docker
  info "Starting vLLM engine (model: ${VLLM_MODEL})..."
  docker run -d \
    --name "${CONTAINER_VLLM}" \
    --gpus=all --runtime=nvidia \
    -p "${VLLM_PORT}:8000" \
    "${VLLM_IMAGE}" \
    --model "${VLLM_MODEL}" \
    --gpu-memory-utilization "${VLLM_GPU_MEMORY_UTIL}" \
    --host 0.0.0.0 >/dev/null
  info "vLLM running on port ${VLLM_PORT}."
}

start_engine_lmstudio() {
  local lms_bin=""
  if command -v lms >/dev/null 2>&1; then
    lms_bin="lms"
  elif [[ -x "/usr/local/bin/lmstudio" ]]; then
    lms_bin="/usr/local/bin/lmstudio"
  elif [[ -x "${HOME}/.local/bin/lms" ]]; then
    lms_bin="${HOME}/.local/bin/lms"
  else
    die "LMStudio CLI (lms) not found. Install it first."
  fi
  info "Starting LMStudio server on port ${LMSTUDIO_PORT}..."
  "${lms_bin}" server start --port "${LMSTUDIO_PORT}" 2>/dev/null &
  info "LMStudio running on port ${LMSTUDIO_PORT}."
}

start_webui() {
  local engine="$1"
  local api_base
  api_base=$(engine_api_base "${engine}")
  require_docker
  info "Starting OpenWebUI (connecting to ${engine})..."
  docker run -d \
    --name "${CONTAINER_WEBUI}" \
    --add-host=host.docker.internal:host-gateway \
    -p "${WEBUI_PORT}:8080" \
    -v "${WEBUI_VOLUME}:/app/backend/data" \
    -e OPENAI_API_BASE_URL="${api_base}" \
    "${WEBUI_IMAGE}" >/dev/null
  info "OpenWebUI running on port ${WEBUI_PORT}."
}

###############################################################################
# Commands
###############################################################################
cmd_start() {
  local engine="${1:-}"
  [[ -z "${engine}" ]] && die "Usage: start <ollama|vllm|lmstudio>"
  validate_engine "${engine}"
  load_config

  # Stop any currently running engine first
  local active
  active=$(get_active_engine)
  if [[ -n "${active}" ]]; then
    info "Stopping currently active engine (${active})..."
    stop_engine "${active}"
    stop_webui
  fi

  case "${engine}" in
    ollama)   start_engine_ollama ;;
    vllm)     start_engine_vllm ;;
    lmstudio) start_engine_lmstudio ;;
  esac

  set_active_engine "${engine}"
  start_webui "${engine}"
  info "Stack ready: ${engine} + OpenWebUI"
}

cmd_stop() {
  local target="${1:-all}"
  load_config

  case "${target}" in
    all)
      stop_all_engines
      stop_webui
      clear_active_engine
      info "All services stopped."
      ;;
    webui)
      stop_webui
      info "OpenWebUI stopped."
      ;;
    *)
      validate_engine "${target}"
      stop_engine "${target}"
      local active
      active=$(get_active_engine)
      if [[ "${active}" == "${target}" ]]; then
        clear_active_engine
      fi
      info "${target} stopped."
      ;;
  esac
}

cmd_restart() {
  local engine="${1:-}"
  [[ -z "${engine}" ]] && die "Usage: restart <ollama|vllm|lmstudio>"
  validate_engine "${engine}"
  cmd_stop all
  cmd_start "${engine}"
}

cmd_status() {
  load_config
  local active
  active=$(get_active_engine)

  echo "--- LLM Manager Status ---"
  echo ""

  # Engine status
  echo "Active engine: ${active:-none}"
  echo ""

  for e in "${ENGINES[@]}"; do
    local cname state="stopped"
    cname=$(engine_container_name "$e")
    if [[ "$e" == "lmstudio" ]]; then
      if pgrep -f "lmstudio|lms server" >/dev/null 2>&1; then
        state="running (port $(engine_port "$e"))"
      fi
    elif [[ -n "${cname}" ]] && container_running "${cname}"; then
      state="running (port $(engine_port "$e"))"
    fi
    printf "  %-12s %s\n" "${e}:" "${state}"
  done

  # WebUI
  local webui_state="stopped"
  if container_running "${CONTAINER_WEBUI}"; then
    webui_state="running (port ${WEBUI_PORT})"
  fi
  printf "  %-12s %s\n" "webui:" "${webui_state}"

  echo ""

  # GPU info
  if command -v nvidia-smi >/dev/null 2>&1; then
    echo "--- GPU ---"
    nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu \
      --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r name mem_used mem_total gpu_util; do
      printf "  %s  Memory: %s/%s MiB  GPU Util: %s%%\n" \
        "$(echo "${name}" | xargs)" \
        "$(echo "${mem_used}" | xargs)" \
        "$(echo "${mem_total}" | xargs)" \
        "$(echo "${gpu_util}" | xargs)"
    done
  fi
}

cmd_update() {
  local target="${1:-all}"
  load_config
  require_docker

  update_image() {
    local image="$1" label="$2"
    info "Pulling latest ${label} image (${image})..."
    docker pull "${image}"
  }

  case "${target}" in
    ollama)
      update_image "${OLLAMA_IMAGE}" "Ollama"
      ;;
    vllm)
      update_image "${VLLM_IMAGE}" "vLLM"
      ;;
    lmstudio)
      warn "LMStudio is installed natively — update it via the LMStudio app or CLI."
      ;;
    webui)
      update_image "${WEBUI_IMAGE}" "OpenWebUI"
      ;;
    all)
      update_image "${OLLAMA_IMAGE}" "Ollama"
      update_image "${VLLM_IMAGE}" "vLLM"
      update_image "${WEBUI_IMAGE}" "OpenWebUI"
      info "All Docker images updated."
      ;;
    *)
      die "Usage: update [ollama|vllm|lmstudio|webui|all]"
      ;;
  esac
}

cmd_logs() {
  local target="${1:-}"
  [[ -z "${target}" ]] && die "Usage: logs <ollama|vllm|webui>"
  load_config

  local cname=""
  case "${target}" in
    ollama) cname="${CONTAINER_OLLAMA}" ;;
    vllm)   cname="${CONTAINER_VLLM}" ;;
    webui)  cname="${CONTAINER_WEBUI}" ;;
    lmstudio) die "LMStudio runs natively — check its own log output." ;;
    *) die "Usage: logs <ollama|vllm|webui>" ;;
  esac

  require_docker
  if container_running "${cname}" || container_exists "${cname}"; then
    docker logs -f "${cname}"
  else
    die "Container ${cname} is not running."
  fi
}

cmd_models() {
  local sub="${1:-}" name="${2:-}"
  load_config
  local active
  active=$(get_active_engine)
  [[ -z "${active}" ]] && die "No engine is currently active. Start one first."

  case "${sub}" in
    list)
      case "${active}" in
        ollama)
          local port
          port=$(engine_port ollama)
          info "Models on Ollama:"
          curl -s "http://localhost:${port}/api/tags" | \
            python3 -m json.tool 2>/dev/null || \
            curl -s "http://localhost:${port}/api/tags"
          ;;
        vllm)
          local port
          port=$(engine_port vllm)
          info "Models on vLLM:"
          curl -s "http://localhost:${port}/v1/models" | \
            python3 -m json.tool 2>/dev/null || \
            curl -s "http://localhost:${port}/v1/models"
          ;;
        lmstudio)
          if command -v lms >/dev/null 2>&1; then
            lms ls
          else
            local port
            port=$(engine_port lmstudio)
            curl -s "http://localhost:${port}/v1/models" | \
              python3 -m json.tool 2>/dev/null || \
              curl -s "http://localhost:${port}/v1/models"
          fi
          ;;
      esac
      ;;
    pull)
      [[ -z "${name}" ]] && die "Usage: models pull <model-name>"
      case "${active}" in
        ollama)
          local port
          port=$(engine_port ollama)
          info "Pulling model '${name}' on Ollama..."
          curl -s -X POST "http://localhost:${port}/api/pull" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"${name}\"}"
          echo ""
          ;;
        vllm)
          warn "vLLM loads models at startup. Set the model with: config set VLLM_MODEL ${name}"
          warn "Then restart: restart vllm"
          ;;
        lmstudio)
          if command -v lms >/dev/null 2>&1; then
            lms pull "${name}"
          else
            die "LMStudio CLI not found. Install models via the LMStudio app."
          fi
          ;;
      esac
      ;;
    rm)
      [[ -z "${name}" ]] && die "Usage: models rm <model-name>"
      case "${active}" in
        ollama)
          local port
          port=$(engine_port ollama)
          info "Removing model '${name}' from Ollama..."
          curl -s -X DELETE "http://localhost:${port}/api/delete" \
            -H "Content-Type: application/json" \
            -d "{\"name\": \"${name}\"}"
          echo ""
          ;;
        vllm)
          warn "vLLM doesn't support runtime model removal."
          ;;
        lmstudio)
          if command -v lms >/dev/null 2>&1; then
            lms rm "${name}"
          else
            die "LMStudio CLI not found. Remove models via the LMStudio app."
          fi
          ;;
      esac
      ;;
    *)
      die "Usage: models <list|pull|rm> [model-name]"
      ;;
  esac
}

cmd_config() {
  local sub="${1:-}" key="${2:-}" value="${3:-}"
  case "${sub}" in
    show)  config_show ;;
    set)   config_set "${key}" "${value}" ;;
    reset) config_reset ;;
    *)     die "Usage: config <show|set|reset>" ;;
  esac
}

###############################################################################
# Signal handling
###############################################################################
cleanup() {
  echo ""
  info "Signal received; cleaning up..."
  load_config
  stop_all_engines
  stop_webui
  clear_active_engine
  exit 0
}

###############################################################################
# Main
###############################################################################
main() {
  local cmd="${1:-}"
  shift 2>/dev/null || true

  case "${cmd}" in
    start)   cmd_start "$@" ;;
    stop)    cmd_stop "$@" ;;
    restart) cmd_restart "$@" ;;
    status)  cmd_status "$@" ;;
    update)  cmd_update "$@" ;;
    logs)    cmd_logs "$@" ;;
    models)  cmd_models "$@" ;;
    config)  cmd_config "$@" ;;
    help|-h|--help) usage 0 ;;
    *)       usage 1 ;;
  esac
}

# Only trap on long-running commands (start runs and exits; the trap is for
# interactive use if the script were to be kept alive like the old script).
trap cleanup INT TERM HUP QUIT

main "$@"
