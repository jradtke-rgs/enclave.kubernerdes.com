#!/usr/bin/env bash
set -euo pipefail

# Purpose:  Start vLLM natively on DGX Spark (no Docker, no systemd)
#  Status:  working
#   Notes:  Sources ~/.bashrc.d/AI for HF_TOKEN (required for gated models).
#           Config persisted to ~/.config/vllm/config; CLI flags override.
#           Native (non-Docker) install avoids UMA memory-visibility issues.
#
# Usage: start_vllm.sh [--model <hf-id>] [--port <n>] [--max-model-len <n>]
#                       [--gpu-mem-util <0.0-1.0>] [--dtype <auto|bfloat16|float16>]
#                       [--extra-args <"...">] [stop]
#
# Defaults (override in ~/.config/vllm/config or via CLI):
#   VLLM_MODEL          nvidia/Nemotron-3-Super-120B-A12B   (NVFP4 fits in 128 GB UMA)
#   VLLM_PORT           8000
#   VLLM_GPU_MEM_UTIL   0.90
#   VLLM_MAX_MODEL_LEN  8192
#   VLLM_DTYPE          auto
#   VLLM_EXTRA_ARGS     (empty)

CONFIG_DIR="${HOME}/.config/vllm"
CONFIG_FILE="${CONFIG_DIR}/config"
VENV_MARKER="${CONFIG_DIR}/venv_path"
PID_FILE="${CONFIG_DIR}/vllm.pid"
LOG_FILE="${CONFIG_DIR}/vllm.log"

###############################################################################
# Helpers
###############################################################################
info() { echo "==> $*"; }
die()  { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }

###############################################################################
# Load config (file first, then CLI flags override)
###############################################################################
VLLM_MODEL="nvidia/Nemotron-3-Super-120B-A12B"
VLLM_PORT="8000"
VLLM_GPU_MEM_UTIL="0.90"
VLLM_MAX_MODEL_LEN="8192"
VLLM_DTYPE="auto"
VLLM_EXTRA_ARGS=""

mkdir -p "${CONFIG_DIR}"
if [[ -f "${CONFIG_FILE}" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    declare "${key}=${value}"
  done < "${CONFIG_FILE}"
fi

###############################################################################
# Parse CLI args
###############################################################################
SUBCMD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    stop)             SUBCMD="stop"; shift ;;
    status)           SUBCMD="status"; shift ;;
    logs)             SUBCMD="logs"; shift ;;
    --model)          VLLM_MODEL="${2:-}"; shift 2 ;;
    --port)           VLLM_PORT="${2:-}"; shift 2 ;;
    --gpu-mem-util)   VLLM_GPU_MEM_UTIL="${2:-}"; shift 2 ;;
    --max-model-len)  VLLM_MAX_MODEL_LEN="${2:-}"; shift 2 ;;
    --dtype)          VLLM_DTYPE="${2:-}"; shift 2 ;;
    --extra-args)     VLLM_EXTRA_ARGS="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '/^# Usage:/,/^[^#]/{ /^#/{ s/^# \{0,2\}//; p } }' "$0"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

###############################################################################
# Sub-commands: stop / status / logs
###############################################################################
do_stop() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}")"
    if kill -0 "${pid}" 2>/dev/null; then
      info "Stopping vLLM (pid ${pid})..."
      kill "${pid}"
      rm -f "${PID_FILE}"
      info "Stopped."
    else
      warn "PID ${pid} is not running."
      rm -f "${PID_FILE}"
    fi
  else
    info "vLLM does not appear to be running (no pid file)."
  fi
}

do_status() {
  if [[ -f "${PID_FILE}" ]]; then
    local pid
    pid="$(cat "${PID_FILE}")"
    if kill -0 "${pid}" 2>/dev/null; then
      info "vLLM is running (pid ${pid}, port ${VLLM_PORT})"
      info "Model: ${VLLM_MODEL}"
      info "Log:   ${LOG_FILE}"
    else
      warn "Stale pid file — vLLM is not running."
    fi
  else
    info "vLLM is not running."
  fi
}

do_logs() {
  [[ -f "${LOG_FILE}" ]] || die "Log file not found: ${LOG_FILE}"
  tail -f "${LOG_FILE}"
}

case "${SUBCMD}" in
  stop)   do_stop;   exit 0 ;;
  status) do_status; exit 0 ;;
  logs)   do_logs;   exit 0 ;;
esac

###############################################################################
# Guard: already running?
###############################################################################
if [[ -f "${PID_FILE}" ]]; then
  pid="$(cat "${PID_FILE}")"
  if kill -0 "${pid}" 2>/dev/null; then
    die "vLLM already running (pid ${pid}). Run '$(basename "$0") stop' first."
  fi
  rm -f "${PID_FILE}"
fi

###############################################################################
# Locate venv
###############################################################################
VENV_DIR=""
if [[ -f "${VENV_MARKER}" ]]; then
  VENV_DIR="$(cat "${VENV_MARKER}")"
fi
if [[ -z "${VENV_DIR}" || ! -f "${VENV_DIR}/bin/activate" ]]; then
  die "vLLM venv not found. Run install_vllm.sh first."
fi
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

command -v vllm &>/dev/null || die "vllm binary not found in venv (${VENV_DIR}). Re-run install_vllm.sh."

###############################################################################
# HuggingFace token (needed for gated/NVIDIA models)
###############################################################################
if [[ -z "${HF_TOKEN:-}" && -f "${HOME}/.bashrc.d/AI" ]]; then
  # shellcheck source=/dev/null
  source "${HOME}/.bashrc.d/AI"
fi
if [[ -z "${HF_TOKEN:-}" ]]; then
  warn "HF_TOKEN is not set — gated models (like Nemotron) will fail to download."
  warn "Add 'export HF_TOKEN=hf_...' to ~/.bashrc.d/AI"
fi

###############################################################################
# Launch
###############################################################################
info "Starting vLLM..."
info "  Model:           ${VLLM_MODEL}"
info "  Port:            ${VLLM_PORT}"
info "  GPU mem util:    ${VLLM_GPU_MEM_UTIL}"
info "  Max model len:   ${VLLM_MAX_MODEL_LEN}"
info "  dtype:           ${VLLM_DTYPE}"
info "  Log:             ${LOG_FILE}"
info ""
info "Note: DGX Spark uses a Unified Memory Architecture (UMA). vLLM will see"
info "the full shared memory pool (~128 GB). --gpu-memory-utilization=${VLLM_GPU_MEM_UTIL}"
info "reserves that fraction for weights + KV cache."

# Build argument list
VLLM_ARGS=(
  serve "${VLLM_MODEL}"
  --host 0.0.0.0
  --port "${VLLM_PORT}"
  --gpu-memory-utilization "${VLLM_GPU_MEM_UTIL}"
  --max-model-len "${VLLM_MAX_MODEL_LEN}"
  --dtype "${VLLM_DTYPE}"
  --tensor-parallel-size 1
)
# Append any extra pass-through args
# shellcheck disable=SC2206
[[ -n "${VLLM_EXTRA_ARGS}" ]] && VLLM_ARGS+=( ${VLLM_EXTRA_ARGS} )

nohup vllm "${VLLM_ARGS[@]}" >> "${LOG_FILE}" 2>&1 &
VLLM_PID=$!
echo "${VLLM_PID}" > "${PID_FILE}"

info ""
info "vLLM started in background (pid ${VLLM_PID})."
info "  API: http://0.0.0.0:${VLLM_PORT}/v1"
info "  Logs:   $(basename "$0") logs      (or: tail -f ${LOG_FILE})"
info "  Stop:   $(basename "$0") stop"
info "  Status: $(basename "$0") status"
info ""
info "Model download + engine init takes several minutes on first run."
info "Watch the log to see when the server is ready."
