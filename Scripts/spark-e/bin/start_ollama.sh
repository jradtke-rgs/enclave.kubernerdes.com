#!/usr/bin/env bash
# start_ollama.sh — Launch the bundled OpenWebUI+Ollama container.
#
# NOTE: This uses the ghcr.io/open-webui/open-webui:ollama bundled image,
# which co-locates Ollama and the WebUI in a single container.  The preferred
# architecture (per llm-manager) is to run them as separate containers; this
# script is retained for simple/standalone use.
set -euo pipefail

readonly CONTAINER_NAME="open-webui"
readonly IMAGE="ghcr.io/open-webui/open-webui:ollama"
readonly WEBUI_PORT="12000"
readonly OLLAMA_PORT="11434"

# Whether *this* invocation started (or created) the container.
# Only clean up what we own.
_started=false

# ── Helpers ──────────────────────────────────────────────────────────────────

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*"; }
err() { log "ERROR: $*" >&2; }

container_running() {
  docker ps -q --filter "name=^${CONTAINER_NAME}$" --filter "status=running" \
    | grep -q .
}

container_exists() {
  docker ps -aq --filter "name=^${CONTAINER_NAME}$" | grep -q .
}

# ── Signal handling ───────────────────────────────────────────────────────────

cleanup() {
  if [[ "${_started}" == true ]]; then
    log "Signal received; stopping ${CONTAINER_NAME}..."
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM HUP QUIT

# ── Preflight ─────────────────────────────────────────────────────────────────

if ! docker info >/dev/null 2>&1; then
  err "Docker daemon is not reachable."
  exit 1
fi

# ── Container lifecycle ───────────────────────────────────────────────────────

if container_running; then
  log "${CONTAINER_NAME} is already running — attaching."
elif container_exists; then
  log "Starting existing container ${CONTAINER_NAME}..."
  docker start "${CONTAINER_NAME}" >/dev/null
  _started=true
else
  log "Creating and starting ${CONTAINER_NAME}..."
  docker run -d \
    --name "${CONTAINER_NAME}" \
    --gpus all \
    --runtime=nvidia \
    -p "${WEBUI_PORT}:8080" \
    -p "${OLLAMA_PORT}:${OLLAMA_PORT}" \
    -v llm-manager-webui:/app/backend/data \
    -v llm-manager-ollama:/root/.ollama \
    -e OLLAMA_HOST="0.0.0.0:${OLLAMA_PORT}" \
    "${IMAGE}" >/dev/null
  _started=true
fi

log "WebUI → http://0.0.0.0:${WEBUI_PORT}   Ollama → http://0.0.0.0:${OLLAMA_PORT}   (Ctrl+C to stop)"

# Block until the container stops; EXIT trap handles cleanup.
docker wait "${CONTAINER_NAME}" >/dev/null 2>&1 || true
