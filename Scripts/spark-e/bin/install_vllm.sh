#!/usr/bin/env bash
set -euo pipefail

# Purpose:  Install vLLM natively (pip/venv) on DGX Spark
#  Status:  working
#   Notes:  Installs into ~/.local/venv/vllm so it stays isolated.
#           Native install (not Docker) avoids UMA visibility issues
#           that affect containerised GPU runtimes on DGX Spark.
#           Requires Python 3.10+ and CUDA toolkit (pre-installed on DGX OS).
#
# Usage: bash install_vllm.sh [--model <hf-model-id>]
#        --model  Pre-download a HuggingFace model into ~/.cache/huggingface
#                 (optional; you can also pull at start time via start_vllm.sh)

VENV_DIR="${HOME}/.local/venv/vllm"
MIN_PYTHON_MINOR=10

###############################################################################
# Helpers
###############################################################################
info() { echo "==> $*"; }
die()  { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }

###############################################################################
# Parse args
###############################################################################
PREFETCH_MODEL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) PREFETCH_MODEL="${2:-}"; shift 2 ;;
    -h|--help)
      echo "Usage: $(basename "$0") [--model <hf-model-id>]"
      exit 0
      ;;
    *) die "Unknown argument: $1" ;;
  esac
done

###############################################################################
# Preflight checks
###############################################################################
info "Checking prerequisites..."

# Python
PYTHON_BIN=""
for candidate in python3.12 python3.11 python3.10 python3; do
  if command -v "${candidate}" &>/dev/null; then
    minor="$("${candidate}" -c 'import sys; print(sys.version_info.minor)')"
    major="$("${candidate}" -c 'import sys; print(sys.version_info.major)')"
    if [[ "${major}" -eq 3 && "${minor}" -ge "${MIN_PYTHON_MINOR}" ]]; then
      PYTHON_BIN="${candidate}"
      break
    fi
  fi
done
[[ -z "${PYTHON_BIN}" ]] && die "Python 3.${MIN_PYTHON_MINOR}+ not found. Install it first."
info "Using Python: $(command -v "${PYTHON_BIN}") ($("${PYTHON_BIN}" --version))"

# CUDA
if ! command -v nvcc &>/dev/null && ! [[ -d /usr/local/cuda ]]; then
  warn "CUDA toolkit not found in PATH or /usr/local/cuda — vLLM requires CUDA."
  warn "On DGX Spark, CUDA is pre-installed; check your PATH includes /usr/local/cuda/bin."
fi

# pip
"${PYTHON_BIN}" -m pip --version &>/dev/null || die "pip not available for ${PYTHON_BIN}."

###############################################################################
# Create / update venv
###############################################################################
if [[ -d "${VENV_DIR}" ]]; then
  info "venv already exists at ${VENV_DIR} — upgrading vLLM..."
else
  info "Creating venv at ${VENV_DIR}..."
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
fi

# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

info "Upgrading pip/setuptools/wheel..."
pip install --quiet --upgrade pip setuptools wheel

###############################################################################
# Install vLLM
###############################################################################
info "Installing vLLM (this may take a few minutes)..."
# vLLM publishes CUDA-enabled wheels on PyPI; the right wheel is selected
# automatically based on your installed CUDA runtime.
pip install vllm

info "vLLM installed: $(pip show vllm | grep ^Version)"

###############################################################################
# Optional: pre-fetch a model
###############################################################################
if [[ -n "${PREFETCH_MODEL}" ]]; then
  info "Pre-downloading model '${PREFETCH_MODEL}' to ~/.cache/huggingface ..."
  if [[ -z "${HF_TOKEN:-}" && -f "${HOME}/.bashrc.d/AI" ]]; then
    # shellcheck source=/dev/null
    source "${HOME}/.bashrc.d/AI"
  fi
  HF_TOKEN_ARG=""
  [[ -n "${HF_TOKEN:-}" ]] && HF_TOKEN_ARG="--token ${HF_TOKEN}"
  # Use huggingface-hub CLI (installed as a vLLM dependency)
  # shellcheck disable=SC2086
  huggingface-cli download "${PREFETCH_MODEL}" ${HF_TOKEN_ARG}
  info "Model downloaded."
fi

###############################################################################
# Write a venv-activate helper so start_vllm.sh can find the venv
###############################################################################
VENV_MARKER="${HOME}/.config/vllm/venv_path"
mkdir -p "$(dirname "${VENV_MARKER}")"
echo "${VENV_DIR}" > "${VENV_MARKER}"
info "venv path written to ${VENV_MARKER}"

###############################################################################
# Done
###############################################################################
info "Installation complete."
info ""
info "Next steps:"
info "  1. Copy start_vllm.sh to ~/bin/ and make it executable:"
info "       install -m 0755 start_vllm.sh ~/bin/start_vllm.sh"
info "  2. Start vLLM with a model:"
info "       ~/bin/start_vllm.sh --model meta-llama/Llama-3.1-8B-Instruct"
info "  3. (Optional) set a default model so you can just run ~/bin/start_vllm.sh:"
info "       echo 'VLLM_MODEL=meta-llama/Llama-3.1-8B-Instruct' >> ~/.config/vllm/config"
