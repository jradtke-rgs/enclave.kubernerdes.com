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
HARBOR_REGISTRY="harbor.enclave.kubernerdes.com"
CERTMGR_VERSION="v1.18.0"
RANCHER_VERSION="2.13.3"        # NOTE: no leading 'v' for helm chart version
RANCHER_HOSTNAME="rancher.enclave.kubernerdes.com"

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml"

# cert-manager chart in Harbor: third-party-charts/hauler/cert-manager
# cert-manager images in Harbor: third-party-charts/jetstack/<image>
helm upgrade --install cert-manager \
  oci://${HARBOR_REGISTRY}/third-party-charts/hauler/cert-manager \
  --version "${CERTMGR_VERSION}" \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=false \
  --set image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-controller" \
  --set webhook.image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-webhook" \
  --set cainjector.image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-cainjector" \
  --set startupapicheck.image.repository="${HARBOR_REGISTRY}/third-party-charts/jetstack/cert-manager-startupapicheck"

kubectl -n cert-manager rollout status deploy/cert-manager

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
