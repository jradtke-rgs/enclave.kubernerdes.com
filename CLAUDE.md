# CLAUDE.md — spark-e Scripts

## Project Overview
Scripts for managing LLM infrastructure on an NVIDIA DGX Spark (DGX OS / Ubuntu-based).

## Key Files
- `llm-manager.sh` — Unified LLM stack manager (Ollama, vLLM, LMStudio + OpenWebUI)

## Architecture
- **One engine at a time**: Only one LLM engine (Ollama, vLLM, or LMStudio) runs at any given time. Starting a new engine automatically stops the current one.
- **OpenWebUI** runs as a separate container (not the bundled ollama image) and auto-connects to whichever engine is active.
- **Docker-based engines** (Ollama, vLLM) use `--gpus=all --runtime=nvidia` for GPU passthrough.
- **LMStudio** is native (not containerized); managed via the `lms` CLI.
- Config persisted to `~/.config/llm-manager/config`; active engine tracked in `~/.config/llm-manager/active`.

## Container Names
| Service   | Container Name |
|-----------|---------------|
| Ollama    | `llm-ollama`  |
| vLLM      | `llm-vllm`    |
| OpenWebUI | `open-webui`  |

## Conventions
- Scripts use `bash` with `set -euo pipefail`.
- All services bind to `0.0.0.0` for LAN accessibility.
- Docker volumes are prefixed with `llm-manager-` (e.g., `llm-manager-ollama`, `llm-manager-webui`).
