# https://build.nvidia.com/spark/nim-llm/instructions
# https://docs.nvidia.com/nim/ingestion/image-ocr/latest/getting-started.html

# Test that GPU access is enabled
docker run -it --gpus=all nvcr.io/nvidia/cuda:13.0.1-devel-ubuntu24.04 nvidia-smi


echo "export NGC_API_KEY=<value>" >> ~/.bashrc.d/AI

echo "$NGC_API_KEY" | docker login nvcr.io --username '$oauthtoken' --password-stdin

# nemotron-3-super-120b-a12b-nvfp4
# nemotron-3-super-120b-a12b-bf16
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
  -e NGC_API_KEY \
  -v "\$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -u \$(id -u) \
  -p 8000:8000 \
  \$IMG_NAME
EOF
chmod 0755 ~/bin/launch_NIM.sh

clear; cat ~/bin/launch_NIM.sh
