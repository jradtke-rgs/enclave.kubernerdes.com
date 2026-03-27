# 10_install_rancher_manager.sh — Deploy RKE2 + Rancher Manager Server
#
# Not intended to be run as a script — cut and paste sections as needed.
# Run from the admin node (nuc-00) or any host with kubectl + helm access.
#
# Prerequisites:
#   - 3 SL-Micro VMs deployed on Harvester (rancher-01/02/03)
#   - RKE2 installed on all 3 VMs (see Scripts/install_RKE2.sh)
#   - KUBECONFIG for the rancher cluster copied to ~/.kube/enclave-rancher.kubeconfig
#   - hauler store serving registry on port 5000 (hauler store serve registry)
#
# Reference:
#   https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli

# ---------------------------------------------------------------------------
# Deploy the 3 Rancher VMs on Harvester
# ---------------------------------------------------------------------------
# Create 3 VMs in Harvester UI (or via API):
#   - OS: SL-Micro 6.1 (from internal registry or ISO served by nuc-00)
#   - CPU: 4 vCPU, RAM: 8GB, Disk: 50GB
#   - Hostnames: rancher-01, rancher-02, rancher-03
#   - IPs: 10.10.12.211, .212, .213  (static, per DNS zone)
#
# Then run Scripts/install_RKE2.sh on each VM (see that script for details).

# ---------------------------------------------------------------------------
# Retrieve kubeconfig from rancher-01 after RKE2 is up
# ---------------------------------------------------------------------------
scp sles@rancher-01:.kube/config ~/.kube/enclave-rancher.kubeconfig
sed -i -e 's/127.0.0.1/10.10.12.210/g' ~/.kube/enclave-rancher.kubeconfig   # use VIP
export KUBECONFIG=~/.kube/enclave-rancher.kubeconfig
kubectl get nodes

# ---------------------------------------------------------------------------
# cert-manager — from hauler registry (no public pull)
# ---------------------------------------------------------------------------
INTERNAL_REGISTRY="10.10.12.10:5000"
CERTMGR_VERSION="v1.18.0"
RANCHER_VERSION="v2.13.3"
RANCHER_HOSTNAME="rancher.enclave.kubernerdes.com"

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml"

# cert-manager chart was hauled into the store — serve via hauler registry
helm upgrade --install cert-manager \
  oci://${INTERNAL_REGISTRY}/charts/cert-manager \
  --version "${CERTMGR_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-controller" \
  --set webhook.image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-webhook" \
  --set cainjector.image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-cainjector" \
  --set startupapicheck.image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-startupapicheck"

kubectl -n cert-manager rollout status deploy/cert-manager

# ---------------------------------------------------------------------------
# Rancher Manager — from hauler registry
# ---------------------------------------------------------------------------
kubectl create namespace cattle-system

helm upgrade --install rancher \
  oci://${INTERNAL_REGISTRY}/charts/rancher \
  --version "${RANCHER_VERSION}" \
  --namespace cattle-system \
  --set hostname="${RANCHER_HOSTNAME}" \
  --set replicas=3 \
  --set bootstrapPassword=ChangeMe-RancherBootstrap \
  --set rancherImage="${INTERNAL_REGISTRY}/rancher/rancher" \
  --set systemDefaultRegistry="${INTERNAL_REGISTRY}"

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
