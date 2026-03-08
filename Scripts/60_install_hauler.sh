#!/bin/bash

# NOTE:  I install and configure hauler on the infra node which also hosts HTML content (nuc-00)
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
hauler completion bash >> ~/.bashrc.d/HAULER-completion

cat << EOF > ~/.bashrc.d/HAULER
#HAULER_DIR=
#HAULER_TEMP_DIR=
HAULER_STORE_DIR=/srv/www/htdocs/hauler/store
HAULER_CREDS_FILE=~/.hauler/credentials

[ -f $HAULER_CREDS_FILE ] && source $HAULER_CREDS_FILE
alias HAULER_LOGIN="$(which hauler) login \$HAULER_SOURCE_REPO_URL -u \$HAULER_USER -p \$HAULER_PASSWORD"
EOF
. $CREDS_FILE

cat << EOF >> ~mansible/.bashrc

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
  for rc in ~/.bashrc.d/*; do
  if [ -f "$rc" ]; then
    [ ! -z $TROUBLESHOOT_BASH ] && { echo "### Sourcing: $rc from ~/.bashrc"; }
    . "$rc"
    fi
  done
fi
unset rc

EOF
[ ! -d /srv/www/htdocs/hauler/store ] && sudo mkdir -p /srv/www/htdocs/hauler/store 

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

