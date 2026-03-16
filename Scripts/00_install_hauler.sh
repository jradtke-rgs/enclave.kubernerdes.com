#!/bin/bash

# NOTE:  I install and configure hauler on the infra node which also hosts HTML content (nuc-00)
# https://docs.hauler.dev/docs/introduction/install

sudo su -

# Install cosign (Supply Chain Verification)
COSIGN_BINARY=cosign-linux-amd64
COSIGN_CHECKSUMS=cosign_checksums.txt
TMPDIR="$(mktemp -d)"
curl -fsSL -o ${TMPDIR}/${COSIGN_BINARY} "https://github.com/sigstore/cosign/releases/latest/download/${COSIGN_BINARY}"
curl -fsSL -o ${TMPDIR}/${COSIGN_CHECKSUMS} "https://github.com/sigstore/cosign/releases/latest/download/${COSIGN_CHECKSUMS}"

EXCPECTED_HASH=$(grep -w "${COSIGN_BINARY}" ${COSIGN_CHECKSUMS} | awk '{ print $1 }')
CALCULATED_HASH=$(sha256sum ${COSIGN_BINARY} | awk '{ print $1 }')

if [[ ${EXCPECTED_HASH} != ${CALCULATED_HASH} ]]; then
  echo "ERROR: hash does not match.  Exiting."
  exit 1 
fi
sudo install -m 0755 -o root "${TMPDIR}/${COSIGN_BINARY}" /usr/local/bin/cosign

# Install Hauler
curl -sfL https://get.hauler.dev | sudo bash

CREDS_FILE=~/.hauler/credentials
echo "NOTE: you will need to update $CREDS_FILE"
[ ! -d ~/.hauler ] && mkdir ~/.hauler
cat << EOF | tee $CREDS_FILE
export HAULER_USER=""
export HAULER_PASSWORD=""
export HAULER_SOURCE_REPO_URL="rgcrprod.azurecr.us"
EOF

[ ! -d ~/.bashrc.d/ ] && mkdir ~/.bashrc.d/
hauler completion bash >> ~/.bashrc.d/HAULER-completion

cat << EOF > ~/.bashrc.d/HAULER
#HAULER_DIR=
#HAULER_TEMP_DIR=
export HAULER_STORE_DIR=/srv/www/htdocs/hauler/store
export HAULER_CREDS_FILE=~/.hauler/credentials

[ -f $HAULER_CREDS_FILE ] && source $HAULER_CREDS_FILE
alias HAULER_LOGIN="$(which hauler) login \$HAULER_SOURCE_REPO_URL -u \$HAULER_USER -p \$HAULER_PASSWORD"
EOF
. $CREDS_FILE

HAULER_LOGIN


## HAULER SYNC STORE STUFF FOLLOWS THIS
[ ! -d /srv/www/htdocs/hauler/store ] && sudo mkdir -p /srv/www/htdocs/hauler/store 

# https://rancherfederal.github.io/carbide-docs/docs/registry-docs/downloading-images
curl -sfOL https://raw.githubusercontent.com/rancherfederal/carbide-releases/main/carbide-key.pub
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

### TESTING FOLLOWING THIS LINE
# you need to have access to a cluster
for CONFIG in $(find ~/.kube/*.kubeconfig)
do 
  export KUBECONFIG=$CONFIG
  CURRENT_CONTEXT=$(kubectl config view --minify --output jsonpath='{.current-context}' --kubeconfig $KUBECONFIG)
  CLUSTER_NAME=$(kubectl config view --minify --output jsonpath="{.contexts[?(@.name==\"$CURRENT_CONTEXT\")].context.cluster}" --kubeconfig $KUBECONFIG)
  echo $CLUSTER_NAME 
  #IMAGE_LIST=$(kubectl get pods --all-namespaces --kubeconfig $KUBECONFIG -o jsonpath="{.items[*].spec.containers[*].image}" | sed 's/ /\n/g' | sort | uniq) 
  kubectl get pods --all-namespaces --kubeconfig $KUBECONFIG -o jsonpath="{.items[*].spec.containers[*].image}" | sed 's/ /\n/g' | sort | uniq > ~/.hauler/image_list.$CLUSTER_NAME
  echo 
  sleep 1
done
cd ~/.hauler; cat image_list.* | sort -u > all_image_list
source  ~/.bashrc.d/HAULER
HAULER_LOGIN

# Reset the IMAGE_LIST variable with ALL the packages
IMAGE_LIST=$(cat ~/.hauler/all_image_list)

# add the required formatting for the image list
export IMAGE_LIST_MODIFIED=$(echo "${IMAGE_LIST}" | sed 's/^/    - name: /')

# create the hauler manifest with the updated image list
cat << EOF >> hauler-manifest.yaml
---
apiVersion: content.hauler.cattle.io/v1
kind: Images
metadata:
  name: hauler-cluster-images
spec:
  images:
$IMAGE_LIST_MODIFIED
EOF

hauler store sync --filename ~/.hauler/hauler-manifest.yaml
# hauler store load --filename ~/.hauler/hauler-manifest.yaml

# hauler store sync --products rke2=v1.34.4-rke2r1  --platform linux/amd64
#hauler store sync --products rancher=v2.13.3 --platform linux/amd64
#hauler store sync --products rke2=v1.35.2+rke2r1 --platform linux/amd64
# hauler store sync --products neuvector=v5.4.9 --platform linux/amd64

PRODUCTS="rancher=v2.13.3 rke2=v1.35.2+rke2r1 neuvector=v5.4.9"

for PRODUCT in $PRODUCTS
do 
  echo "NOTE: Now syncing: $PRODUCT"
  hauler store sync --products $PRODUCT --platform linux/amd64
  echo
done
