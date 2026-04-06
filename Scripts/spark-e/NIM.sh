# ============================================================
# DO NOT BOTHER — NIM IS NOT SPARK-AWARE (as of 2026-04)
# ============================================================
#
# NIM calculates gpu_memory_utilization against discrete VRAM.
# DGX Spark uses a Unified Memory Architecture (UMA) where GPU
# and CPU share a single 128 GB pool — there is no discrete VRAM
# to report. NIM sees ~0 GB of "GPU memory" and refuses to load.
#
# The same issue affects native vLLM with NVFP4 quantization.
# Ollama (GGUF) works but performance is poor — it does not
# fully utilise the GB10 tensor cores or UMA bandwidth.
#
# Revisit when: NVIDIA updates NIM to support UMA / Blackwell Spark.
# Track: https://developer.nvidia.com/nim  /  DGX Spark release notes.
# ============================================================


 # https://build.nvidia.com/spark/nim-llm/instructions
# https://docs.nvidia.com/nim/ingestion/image-ocr/latest/getting-started.html

# Test that GPU access is enabled
docker run -it --gpus=all nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04 nvidia-smi

# echo "export NGC_API_KEY=<value>" >> ~/.bashrc.d/AI
echo "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin

# setup local caches, etc..
export LOCAL_NIM_CACHE=~/.cache/nim
export LOCAL_NIM_WORKSPACE=~/.local/share/nim/workspace
mkdir -p "$LOCAL_NIM_WORKSPACE"
chmod -R a+w "$LOCAL_NIM_WORKSPACE"
mkdir -p "$LOCAL_NIM_CACHE"
chmod -R a+w "$LOCAL_NIM_CACHE"

# nemotron-3-super-120b-a12b-nvfp4
# nemotron-3-super-120b-a12b-bf16
# nemotron-3-super-30b-a3b
NIM_MODEL_NAME=nvidia/nemotron-3-super-120b-a12b

cat << EOF | tee ~/bin/launch_NIM.sh
#!/bin/bash
# Choose a container name for bookkeeping
export NIM_MODEL_NAME=${NIM_MODEL_NAME}
export CONTAINER_NAME=\$(basename \$NIM_MODEL_NAME)

# Choose a NIM Image from NGC
export IMG_NAME="nvcr.io/nim/nvidia/\$CONTAINER_NAME"

# Choose a path on your system to cache the downloaded models
export LOCAL_NIM_CACHE=~/.cache/nim
mkdir -p "\$LOCAL_NIM_CACHE"

# Start the NIM
docker run -it --rm --name=\$CONTAINER_NAME \
  --gpus all \
  --shm-size=16GB \
  -e NGC_API_KEY=\$NGC_API_KEY \
  -v "\$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -v "\$LOCAL_NIM_WORKSPACE:/opt/nim/workspace" \
  -u \$(id -u) \
  -p 8000:8000 \
  \$IMG_NAME
EOF
chmod 0755 ~/bin/launch_NIM.sh

clear; cat ~/bin/launch_NIM.sh

~/bin/launch_NIM.sh

curl -X 'POST' \
    'http://0.0.0.0:8000/v1/chat/completions' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d '{
      "model": "meta/llama-3.1-8b-instruct",
      "messages": [
        {
          "role":"system",
          "content":"detailed thinking on"
        },
        {
          "role":"user",
          "content":"Can you write me a song?"
        }
      ],
      "top_p": 1,
      "n": 1,
      "max_tokens": 15,
      "frequency_penalty": 1.0,
      "stop": ["hello"]

    }'
    

