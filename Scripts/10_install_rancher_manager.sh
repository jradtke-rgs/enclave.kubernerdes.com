# 10_install_rancher_manager.sh — Deploy RKE2 + Rancher Manager Server
#
# Not intended to be run as a script — cut and paste sections as needed.
# Run from the admin node (nuc-00) or any host with kubectl + helm access.
#
# Prerequisites:
#   - 3 SL-Micro VMs deployed on Harvester (rancher-01/02/03)
#   - RKE2 v1.34.x installed on all 3 VMs (see Scripts/install_RKE2.sh)
#   - KUBECONFIG for the rancher cluster copied to ~/.kube/enclave-rancher.kubeconfig
#   - Harbor running on nuc-00 (harbor.enclave.kubernerdes.com, port 443)
#       All hauler stores already pushed to Harbor projects via 03_install_harbor.sh
#   - hauler fileserver still needed for RKE2 install script:
#       hauler store serve fileserver --store /root/hauler/store/files --port 8080
#   - Enclave root CA trusted on all cluster nodes (see install_RKE2.sh)
#
# Reference:
#   https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli

# ---------------------------------------------------------------------------
# Deploy the 3 Rancher VMs on Harvester
# ---------------------------------------------------------------------------
# Create 3 VMs in Harvester UI (or via API):
#   - OS: SL-Micro 6.1 (from internal registry or ISO served by nuc-00)
#   - CPU: 4 vCPU, RAM: 8GB, Disk: 50GB
#   - Hostnames: rancher-01, rancher-02, rancher-03  (short names, not FQDN)
#   - IPs: 10.10.12.211, .212, .213  (static, per DNS zone)
#
# Then run Scripts/install_RKE2.sh on each VM (see that script for details).

# ---------------------------------------------------------------------------
# Kubeconfig — check for existing file, validate, bail if not usable
# ---------------------------------------------------------------------------
KUBECONFIG_PATH=~/.kube/enclave-rancher.kubeconfig

if [[ ! -f "${KUBECONFIG_PATH}" ]]; then
  echo "ERROR: ${KUBECONFIG_PATH} not found."
  echo "Copy it from rancher-01 with:"
  echo "  scp sles@10.10.12.211:.kube/config ${KUBECONFIG_PATH}"
  echo "  sed -i 's/127.0.0.1/10.10.12.210/g' ${KUBECONFIG_PATH}"
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
# Fetch enclave root CA — required for helm to trust Harbor's TLS cert
# ---------------------------------------------------------------------------
HARBOR_REGISTRY="harbor.enclave.kubernerdes.com"
CERTMGR_VERSION="v1.18.0"
RANCHER_VERSION="2.13.3"        # NOTE: no leading 'v' for helm chart version
RANCHER_HOSTNAME="rancher.enclave.kubernerdes.com"
HAULER_FILESERVER="http://10.10.12.10:8080"
CA_FILE="/tmp/enclave-root-ca.crt"

curl -sfL "${HAULER_FILESERVER}/enclave-root-ca.crt" -o "${CA_FILE}"
echo "==> Enclave root CA fetched: ${CA_FILE}"

# ---------------------------------------------------------------------------
# cert-manager — CRDs installed via chart (crds.enabled=true)
# chart in Harbor: third-party-charts/hauler/cert-manager
# images in Harbor: third-party-charts/jetstack/<image>
# ---------------------------------------------------------------------------
helm upgrade --install cert-manager \
  oci://${HARBOR_REGISTRY}/third-party-charts/hauler/cert-manager \
  --version "${CERTMGR_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --ca-file "${CA_FILE}" \
  --timeout 10m \
  --set crds.enabled=true \
  --set image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-controller" \
  --set webhook.image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-webhook" \
  --set cainjector.image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-cainjector" \
  --set startupapicheck.image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-startupapicheck"

echo "==> Waiting for cert-manager webhook to be ready..."
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=5m
kubectl -n cert-manager wait --for=condition=available deploy/cert-manager-webhook --timeout=5m

# ---------------------------------------------------------------------------
# Rancher Manager — chart from Harbor (third-party-charts/hauler/rancher)
# Images in Harbor: rancher/rancher/<image>
# NOTE: Rancher 2.13.x supports Kubernetes <= 1.34.x.
#       RKE2 must be pinned to v1.34.x (see install_RKE2.sh).
# NOTE: do NOT set image.repository — systemDefaultRegistry prepends the registry.
#       Setting both causes a doubled prefix.
# ---------------------------------------------------------------------------
helm upgrade --install rancher \
  oci://${HARBOR_REGISTRY}/third-party-charts/hauler/rancher \
  --version "${RANCHER_VERSION}" \
  --namespace cattle-system \
  --create-namespace \
  --ca-file "${CA_FILE}" \
  --set hostname="${RANCHER_HOSTNAME}" \
  --set replicas=3 \
  --set bootstrapPassword=ChangeMe-RancherBootstrap \
  --set systemDefaultRegistry="${HARBOR_REGISTRY}/rancher"

kubectl -n cattle-system rollout status deploy/rancher

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

exit 0
