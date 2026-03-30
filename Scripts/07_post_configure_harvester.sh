#!/bin/bash
set -euo pipefail

# prereqs:  You need a kubeconfig to connect to the Harvester API
# Usage:    KUBECONFIG=/path/to/harvester-kubeconfig.yaml ./07_post_configure_harvester.sh

IMAGES_BASE_URL="http://10.10.12.10/images"
TEMPLATES_BASE_URL="http://10.10.12.10/enclave.kubernerdes.com/Files/CloudConfigurationTemplates"

# Sanitize a string into a valid Kubernetes resource name
k8s_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/-\+/-/g' | sed 's/^-//;s/-$//'
}

# ─────────────────────────────────────────────────────────────────
# NETWORKING
# ─────────────────────────────────────────────────────────────────

echo "==> Creating ClusterNetwork: clstrnet-vms"
kubectl apply -f - <<EOF
apiVersion: network.harvesterhci.io/v1beta1
kind: ClusterNetwork
metadata:
  name: clstrnet-vms
  annotations:
    network.harvesterhci.io/description: "Cluster Network for VMs"
spec:
  enable: true
EOF

echo "==> Creating NodeNetwork (Network Configuration): netconf-vms"
# Empty matchLabels matches all nodes — all nodes are identical so one config covers all.
kubectl apply -f - <<EOF
apiVersion: network.harvesterhci.io/v1beta1
kind: NodeNetwork
metadata:
  name: netconf-vms
  namespace: harvester-system
  annotations:
    network.harvesterhci.io/description: "Network Configuration for VMs"
spec:
  clusterNetwork: clstrnet-vms
  nodeSelector:
    matchLabels: {}
  uplink:
    nics:
      - enp0s13f0u1
    bondMode: active-backup
    bondOptions:
      miimon: "100"
EOF

echo "==> Creating VM Network: vmnet-vms (UntaggedNetwork)"
kubectl apply -f - <<EOF
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: vmnet-vms
  namespace: default
  labels:
    network.harvesterhci.io/ready: "true"
  annotations:
    network.harvesterhci.io/route: '{"mode":"auto","serverIPAddr":"","cidr":"","gateway":""}'
spec:
  config: '{"cniVersion":"0.3.1","name":"vmnet-vms","type":"bridge","bridge":"br-clstrnet-vms","promiscMode":true,"vlan":0,"ipam":{}}'
EOF

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
    encoded_content=$(echo "${template_content}" | base64)

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

echo "==> Done."
