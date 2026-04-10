#!/bin/bash
set -euo pipefail

# 10_install_rancher_manager.sh — Deploy cert-manager and Rancher Manager
#
# Run from nuc-00 as mansible with KUBECONFIG pointing to the rancher cluster.
# Prerequisite: install_RKE2_postboot.sh rancher has been run and produced
#   ~/.kube/enclave-rancher.kubeconfig
#
# Charts pulled from upstream helm repos.
# Rancher images pulled from Carbide (rgcrprod.azurecr.us) via systemDefaultRegistry.
# Node-level auth to Carbide is handled by registries.yaml (set during RKE2 install).
#
# Reference:
#   https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
RGS_CREDS="${HOME}/.bashrc.d/RGS"
set +u
[[ -f "${RGS_CREDS}" ]] && source "${RGS_CREDS}" || true
set -u

if [[ -z "${Carbide_Registry_Username:-}" || -z "${Carbide_Registry_Password:-}" ]]; then
  echo "ERROR: Carbide credentials not set. Source ~/.bashrc.d/RGS first."
  exit 1
fi

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
CARBIDE_REGISTRY="rgcrprod.azurecr.us"
CERTMGR_VERSION="v1.18.0"
RANCHER_VERSION="2.13.3"        # no leading 'v' for helm chart version
RANCHER_HOSTNAME="rancher.enclave.kubernerdes.com"
KUBECONFIG_PATH="${HOME}/.kube/enclave-rancher.kubeconfig"

# ---------------------------------------------------------------------------
# Kubeconfig — validate before proceeding
# ---------------------------------------------------------------------------
if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "ERROR: ${KUBECONFIG_PATH} not found."
  echo "Run: bash install_RKE2_postboot.sh rancher"
  exit 1
fi

export KUBECONFIG="${KUBECONFIG_PATH}"

if ! kubectl get nodes --request-timeout=10s > /dev/null 2>&1; then
  echo "ERROR: kubeconfig at ${KUBECONFIG_PATH} is not valid or cluster is unreachable."
  echo "Test manually: kubectl --kubeconfig ${KUBECONFIG_PATH} get nodes"
  exit 1
fi

echo "==> Cluster reachable. Nodes:"
kubectl get nodes

# ---------------------------------------------------------------------------
# Helm repos
# ---------------------------------------------------------------------------
echo "==> Adding helm repos"
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo update

# ---------------------------------------------------------------------------
# cert-manager
# ---------------------------------------------------------------------------
echo "==> Installing cert-manager ${CERTMGR_VERSION}"
helm upgrade --install cert-manager jetstack/cert-manager \
  --version "${CERTMGR_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --timeout 10m \
  --set crds.enabled=true

echo "==> Waiting for cert-manager webhook to be ready..."
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=5m
kubectl -n cert-manager wait --for=condition=available deploy/cert-manager-webhook --timeout=5m

# ---------------------------------------------------------------------------
# Carbide imagePullSecret — required so Rancher can pull hardened images
# ---------------------------------------------------------------------------
echo "==> Creating cattle-system namespace and Carbide imagePullSecret"
kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret docker-registry carbide-registry \
  --namespace cattle-system \
  --docker-server="${CARBIDE_REGISTRY}" \
  --docker-username="${Carbide_Registry_Username}" \
  --docker-password="${Carbide_Registry_Password}" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# Rancher Manager
# NOTE: Rancher 2.13.x supports Kubernetes <= 1.34.x.
#       RKE2 must be pinned to v1.34.x (see install_RKE2.sh).
# ---------------------------------------------------------------------------
echo "==> Installing Rancher ${RANCHER_VERSION}"
helm upgrade --install rancher rancher-stable/rancher \
  --version "${RANCHER_VERSION}" \
  --namespace cattle-system \
  --create-namespace \
  --timeout 10m \
  --set hostname="${RANCHER_HOSTNAME}" \
  --set replicas=3 \
  --set bootstrapPassword=ChangeMe-RancherBootstrap \
  --set systemDefaultRegistry="${CARBIDE_REGISTRY}" \
  --set imagePullSecrets[0].name=carbide-registry

kubectl -n cattle-system rollout status deploy/rancher --timeout=10m

# ---------------------------------------------------------------------------
# Retrieve bootstrap URL
# ---------------------------------------------------------------------------
echo
echo "Rancher UI: https://${RANCHER_HOSTNAME}/dashboard/?setup=$(kubectl get secret \
  --namespace cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}')"

BOOTSTRAP_PASSWORD=$(kubectl get secret --namespace cattle-system bootstrap-secret \
  -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}')
echo "Bootstrap password: ${BOOTSTRAP_PASSWORD}"
