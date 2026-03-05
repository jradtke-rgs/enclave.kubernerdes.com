#!/bin/bash


# NOTE:  I install this on the infra node which also hosts HTML content (nuc-00)
# https://docs.hauler.dev/docs/introduction/install

sudo su -

curl -sfL https://get.hauler.dev | sudo bash
curl -sfOL https://raw.githubusercontent.com/rancherfederal/carbide-releases/main/carbide-key.pub

CREDS_FILE=~/.hauler/credentials
echo "NOTE: you will need to update $CREDS_FILE"
[ ! -d ~/.hauler ] && mkdir ~/.hauler
cat << EOF | tee $CREDS_FILE
HAULER_USER=""
HAULER_PASSWORD=""
HAULER_SOURCE_REPO_URL="rgcrprod.azurecr.us"
EOF
[ ! -d ~/.bashrc.d/ ] && mkdir ~/.bashrc.d/
hauler completion bash >> ~/.bashrc.d/HAULER

cat << EOF > ~/.bashrc.d/HAULER
alias HAULER_LOGIN="$(which hauler) login \$HAULER_SOURCE_REPO_URL -u \$HAULER_USER -p \$HAULER_PASSWORD"
EOF
. $CREDS_FILE

cat <<EOF > carbide-images.yaml
apiVersion: content.hauler.cattle.io/v1
kind: Images
metadata:
  name: carbide-images
spec:
  images:
$(curl -sfL https://raw.githubusercontent.com/rancherfederal/carbide-releases/main/carbide-images.txt | sed '/nats/d' | sed 's/^/    - name: /')
---
apiVersion: content.hauler.cattle.io/v1
kind: Images
metadata:
  name: carbide-dependency-images
spec:
  images:
$(curl -sfL https://raw.githubusercontent.com/rancherfederal/carbide-releases/main/carbide-images.txt | sed '/rgcr/d' | sed 's/^/    - name: /')
EOF

