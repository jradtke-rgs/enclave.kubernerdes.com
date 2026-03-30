# 10_install_rancher_manager.sh — Deploy RKE2 + Rancher Manager Server
#
# Not intended to be run as a script — cut and paste sections as needed.
# Run from the admin node (nuc-00) or any host with kubectl + helm access.
#
# Prerequisites:
#   - 3 SL-Micro VMs deployed on Harvester (rancher-01/02/03)
#   - RKE2 v1.34.x installed on all 3 VMs (see Scripts/install_RKE2.sh)
#   - KUBECONFIG for the rancher cluster copied to ~/.kube/enclave-rancher.kubeconfig
#   - hauler services running on nuc-00 (10.10.12.10):
#       Registry  (port 5000): hauler store serve registry --store /root/hauler/store/rke2
#       Fileserver (port 8080): hauler store serve fileserver --store /root/hauler/store/files
#       Also copy third-party-charts store into registry before this script runs:
#         hauler store copy --store /root/hauler/store/third-party-charts registry://127.0.0.1:5000 --plain-http
#   - Firewall on nuc-00 allows ports 5000 and 8080 (firewall-cmd --add-port=5000/tcp --permanent ...)
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
RANCHER_VERSION="2.13.3"        # NOTE: no leading 'v' for helm chart version
RANCHER_HOSTNAME="rancher.enclave.kubernerdes.com"

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml"

# cert-manager chart stored in hauler under hauler/cert-manager (not charts/cert-manager)
# --plain-http required since hauler registry does not use TLS
helm upgrade --install cert-manager \
  oci://${INTERNAL_REGISTRY}/hauler/cert-manager \
  --version "${CERTMGR_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --plain-http \
  --set crds.enabled=false \
  --set image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-controller" \
  --set webhook.image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-webhook" \
  --set cainjector.image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-cainjector" \
  --set startupapicheck.image.repository="${INTERNAL_REGISTRY}/jetstack/cert-manager-startupapicheck"

kubectl -n cert-manager rollout status deploy/cert-manager

# ---------------------------------------------------------------------------
# Rancher Manager — chart from hauler registry (hauler/rancher), images local
# NOTE: Rancher 2.13.x supports Kubernetes <= 1.34.x.
#       RKE2 must be pinned to v1.34.x (see install_RKE2.sh).
# ---------------------------------------------------------------------------
helm upgrade --install rancher \
  oci://${INTERNAL_REGISTRY}/hauler/rancher \
  --version "${RANCHER_VERSION}" \
  --namespace cattle-system \
  --create-namespace \
  --plain-http \
  --set hostname="${RANCHER_HOSTNAME}" \
  --set replicas=3 \
  --set bootstrapPassword=ChangeMe-RancherBootstrap \
  --set image.repository="${INTERNAL_REGISTRY}/rancher/rancher" \
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
