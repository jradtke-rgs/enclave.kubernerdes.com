#!/bin/bash

echo "$MYUSER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/${MYUSER}-sudo

echo "spark-e" | sudo tee /etc/hostname

sudo usermod -aG docker $USER
newgrp docker
docker ps -a

sudo apt  install nvtop

docker pull ghcr.io/open-webui/open-webui:ollama

