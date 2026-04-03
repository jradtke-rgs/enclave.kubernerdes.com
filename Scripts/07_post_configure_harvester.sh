#!/bin/bash
set -euo pipefail

#   RunAs:  root - you need access to the ca.crt file
# prereqs:  You need a kubeconfig to connect to the Harvester API
#           Run from nuc-00 (has enclave CA at /etc/ssl/enclave-ca/ca.crt)
#   Usage:  KUBECONFIG=/path/to/harvester-kubeconfig.yaml ./07_post_configure_harvester.sh

[ -f ~/.kube/enclave-harvester.kubeconfig ] && { export KUBECONFIG=~/.kube/enclave-harvester.kubeconfig; } || { echo "FAIL: KUBECONFIG not found"; exit 9; }

IMAGES_BASE_URL="http://10.10.12.10/images"
TEMPLATES_BASE_URL="http://10.10.12.10/enclave.kubernerdes.com/Files/CloudConfigurationTemplates"

CA_DIR="/etc/ssl/enclave-ca"
HARBOR_REGISTRY="${HARBOR_REGISTRY:-harbor.enclave.kubernerdes.com}"
HARBOR_ADMIN_PASSWORD="${HARBOR_ADMIN_PASSWORD:-${GENERIC_PASSWORD}}"

# ─────────────────────────────────────────────────────────────────
# HARBOR INTEGRATION
# Must be applied BEFORE importing Harvester into Rancher Manager,
# so the cattle-cluster-agent can pull from Harbor on first contact.
# ─────────────────────────────────────────────────────────────────

echo "==> Configuring Harvester: trust enclave root CA"
if [[ ! -f "${CA_DIR}/ca.crt" ]]; then
  echo "    ERROR: CA not found at ${CA_DIR}/ca.crt — run this script from nuc-00"
  exit 1
fi
CA_CERT=$(cat "${CA_DIR}/ca.crt")
kubectl patch setting additional-ca --type merge -p "{\"value\":$(python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" <<< "${CA_CERT}")}"
echo "    Waiting for apply-sync-additional-ca jobs to complete..."
sleep 10
kubectl wait job \
  --for=condition=complete \
  --timeout=120s \
  -l harvesterhci.io/managed=true \
  -n cattle-system 2>/dev/null || echo "    (jobs may have already completed or timed out — check manually)"

echo "==> Configuring Harvester: containerd registry mirror → Harbor"
REGISTRY_JSON=$(python3 -c "
import json
reg = '${HARBOR_REGISTRY}'
pw  = '${HARBOR_ADMIN_PASSWORD}'
print(json.dumps({
  'Mirrors': {reg: {'Endpoints': ['https://' + reg], 'Rewrites': None}},
  'Configs': {reg: {'Auth': {'Username': 'admin', 'Password': pw}, 'TLS': None}},
  'Auths': None
}))
")
kubectl patch setting containerd-registry --type merge -p "{\"value\":$(python3 -c "import sys,json; print(json.dumps(sys.argv[1]))" "${REGISTRY_JSON}")}"
echo "    containerd-registry set — nodes will reconfigure containerd on next sync"
echo "Note: You will need to login to the webUI again."

# Sanitize a string into a valid Kubernetes resource name
k8s_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//'
}

# ─────────────────────────────────────────────────────────────────
# IMAGES
# ─────────────────────────────────────────────────────────────────

echo "==> Discovering .qcow2 images at ${IMAGES_BASE_URL}/"
# Scrape the HTTP autoindex listing for .qcow2 filenames
IMAGE_FILES=$(curl -fsSL "${IMAGES_BASE_URL}/" | grep -oP '(?<=href=")[^"]+\.qcow2(?=")' | sort -u)

if [[ -z "${IMAGE_FILES}" ]]; then
  echo "    No .qcow2 images found — skipping image import."
else
  while IFS= read -r filename; do
    # Strip any leading path components (autoindex sometimes includes them)
    basename_file=$(basename "${filename}")
    display_name="${basename_file}"
    resource_name=$(k8s_name "${basename_file%.qcow2}")
    image_url="${IMAGES_BASE_URL}/${basename_file}"

    echo "    Importing image: ${display_name} (resource: ${resource_name})"
    kubectl apply -f - <<EOF
apiVersion: harvesterhci.io/v1beta1
kind: VirtualMachineImage
metadata:
  name: ${resource_name}
  namespace: default
  annotations:
    harvesterhci.io/storageClassName: harvester-longhorn
spec:
  displayName: "${display_name}"
  sourceType: download
  url: "${image_url}"
EOF
  done <<< "${IMAGE_FILES}"
fi

# ─────────────────────────────────────────────────────────────────
# CLOUD CONFIGURATION TEMPLATES
# ─────────────────────────────────────────────────────────────────

echo "==> Discovering cloud configuration templates at ${TEMPLATES_BASE_URL}/"
TEMPLATE_FILES=$(curl -fsSL "${TEMPLATES_BASE_URL}/" | grep -oP '(?<=href=")[^"]+\.yaml(?=")' | sort -u)

if [[ -z "${TEMPLATE_FILES}" ]]; then
  echo "    No .yaml templates found — skipping cloud config template import."
else
  while IFS= read -r filename; do
    basename_file=$(basename "${filename}")
    template_name="${basename_file%.yaml}"
    resource_name=$(k8s_name "${template_name}")
    template_url="${TEMPLATES_BASE_URL}/${basename_file}"

    echo "    Importing template: ${template_name} (resource: ${resource_name})"
    template_content=$(curl -fsSL "${template_url}")
    encoded_content=$(echo "${template_content}" | base64 -w 0)

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${resource_name}
  namespace: harvester-system
  labels:
    harvesterhci.io/cloud-init-template: "user"
type: Opaque
data:
  cloudInit: ${encoded_content}
EOF
  done <<< "${TEMPLATE_FILES}"
fi

# ─────────────────────────────────────────────────────────────────
# MONITORING ADD-ON
# ─────────────────────────────────────────────────────────────────

echo "==> Enabling rancher-monitoring add-on"
kubectl patch addon rancher-monitoring \
  -n cattle-monitoring-system \
  --type merge \
  -p '{"spec":{"enabled":true}}'
echo "    rancher-monitoring enabled — Prometheus/Grafana/Alertmanager will deploy shortly"

echo "==> Done."
