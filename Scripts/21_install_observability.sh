# 21_install_observability.sh — Deploy RGS (SUSE) Observability
#
# Not intended to be run as a script — cut and paste sections as needed.
# Run from the admin node (nuc-00) with KUBECONFIG pointing to the
# observability cluster.
#
# Prerequisites:
#   - 3 SL-Micro VMs deployed on Harvester (observability-01/02/03)
#   - RKE2 installed on all 3 VMs (Scripts/install_RKE2.sh — observability case)
#   - KUBECONFIG saved as ~/.kube/enclave-observability.kubeconfig
#   - O11Y_LICENSE env var set (SUSE Observability license key)
#   - Harbor running at harbor.enclave.kubernerdes.com with observability images/charts populated
#   - Enclave root CA trusted on all observability cluster nodes (see install_RKE2.sh)
#
# NOTE: SUSE Observability charts are NOT currently in Harbor.
#       Before running, add them to the hauler sync and push to Harbor.
#       Expected chart paths (verify after push):
#         oci://harbor.enclave.kubernerdes.com/<project>/hauler/suse-observability-values
#         oci://harbor.enclave.kubernerdes.com/<project>/hauler/suse-observability
#
# Reference:
#   https://docs.stackstate.com/

HARBOR_REGISTRY="harbor.enclave.kubernerdes.com"
RANCHER_URL="https://rancher.enclave.kubernerdes.com"
O11Y_URL="https://observability.enclave.kubernerdes.com"

export KUBECONFIG=~/.kube/enclave-observability.kubeconfig
kubectl get nodes

# ---------------------------------------------------------------------------
# cert-manager (required by Observability)
# ---------------------------------------------------------------------------
CERTMGR_VERSION="v1.18.0"

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml"

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
# SUSE Observability
# ---------------------------------------------------------------------------
[ -z "${O11Y_LICENSE:-}" ] && { echo "ERROR: O11Y_LICENSE is not set."; exit 1; }

WORK_DIR=~/observability-install
mkdir -p "${WORK_DIR}" && cd "${WORK_DIR}"

# Generate values files from the Observability chart template
export VALUES_DIR="${WORK_DIR}"
helm template \
  --set license="${O11Y_LICENSE}" \
  --set rancherUrl="${RANCHER_URL}" \
  --set baseUrl="${O11Y_URL}" \
  --set sizing.profile='10-nonha' \
  suse-observability-values \
  oci://${HARBOR_REGISTRY}/<project>/hauler/suse-observability-values \  # TODO: confirm project after chart is pushed to Harbor
  --output-dir "${VALUES_DIR}"

# Install Observability
helm upgrade --install suse-observability \
  oci://${HARBOR_REGISTRY}/<project>/hauler/suse-observability \  # TODO: confirm project after chart is pushed to Harbor
  --namespace suse-observability \
  --create-namespace \
  --values "${VALUES_DIR}/suse-observability-values/templates/baseConfig_values.yaml" \
  --values "${VALUES_DIR}/suse-observability-values/templates/sizing_values.yaml" \
  --values "${VALUES_DIR}/suse-observability-values/templates/affinity_values.yaml"

echo "NOTE: Observability takes 15-20 minutes to fully stabilize."
kubectl get pods -n suse-observability -w

# ---------------------------------------------------------------------------
# Ingress (RKE2 uses nginx by default)
# ---------------------------------------------------------------------------
cat << EOF > "${WORK_DIR}/suse-observability-ingress.yaml"
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: suse-observability-ui
  namespace: suse-observability
spec:
  ingressClassName: nginx
  rules:
  - host: observability.enclave.kubernerdes.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: suse-observability-router
            port:
              number: 8080
  tls:
  - hosts:
    - observability.enclave.kubernerdes.com
EOF
kubectl apply -f "${WORK_DIR}/suse-observability-ingress.yaml"

# ---------------------------------------------------------------------------
# Retrieve admin password
# ---------------------------------------------------------------------------
echo "Observability UI : ${O11Y_URL}"
grep 'admin.*password' "$(find ${VALUES_DIR} -name baseConfig_values.yaml)" || true

exit 0
