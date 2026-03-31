# 20_install_RGS_security.sh — Deploy RGS Security (NeuVector) on the apps cluster
#
# Not intended to be run as a script — cut and paste sections as needed.
# Run from the admin node (nuc-00) with KUBECONFIG pointing to the
# apps cluster.
#
# Prerequisites:
#   - apps cluster deployed via Rancher Manager (3-node RKE2 on SL-Micro)
#   - KUBECONFIG saved as ~/.kube/enclave-apps.kubeconfig
#   - Harbor running at harbor.enclave.kubernerdes.com with neuvector project populated
#   - Enclave root CA trusted on all apps cluster nodes (see install_RKE2.sh)
#
# NeuVector helm chart is in Harbor at: third-party-charts/hauler/core:2.8.11
# (chart version 2.8.11 = NeuVector appVersion 5.4.9)
#
# Reference:
#   https://open-docs.neuvector.com/deploying/kubernetes
#   https://ranchermanager.docs.rancher.com/integrations-in-rancher/neuvector

HARBOR_REGISTRY="harbor.enclave.kubernerdes.com"
NEUVECTOR_VERSION="5.4.9"
NEUVECTOR_CHART_VERSION="2.8.11"   # chart version for NeuVector 5.4.9
RANCHER_URL="https://rancher.enclave.kubernerdes.com"

export KUBECONFIG=~/.kube/enclave-apps.kubeconfig
kubectl get nodes

# ---------------------------------------------------------------------------
# NeuVector namespace and imagePullSecret for internal registry
# ---------------------------------------------------------------------------
kubectl create namespace cattle-neuvector-system

# If the hauler registry requires auth, create an imagePullSecret.
# If hauler is serving unauthenticated (default), skip this.
# kubectl create secret docker-registry carbide-registry \
#   --namespace cattle-neuvector-system \
#   --docker-server="${INTERNAL_REGISTRY}" \
#   --docker-username="${Carbide_Registry_Username}" \
#   --docker-password="${Carbide_Registry_Password}"

# ---------------------------------------------------------------------------
# Install NeuVector from Harbor
# Chart:  third-party-charts/hauler/core (chart v2.8.11 = NeuVector 5.4.9)
# Images: neuvector/neuvector/<image>
# ---------------------------------------------------------------------------
helm upgrade --install neuvector \
  oci://${HARBOR_REGISTRY}/third-party-charts/hauler/core \
  --version "${NEUVECTOR_CHART_VERSION}" \
  --namespace cattle-neuvector-system \
  --set manager.svc.type=ClusterIP \
  --set controller.replicas=3 \
  --set cve.scanner.replicas=2 \
  --set controller.pvc.enabled=false \
  --set k3s.enabled=false \
  --set manager.ingress.enabled=false \
  --set global.cattle.url="${RANCHER_URL}" \
  --set registry="${HARBOR_REGISTRY}/neuvector" \
  --set controller.image.repository="${HARBOR_REGISTRY}/neuvector/neuvector/controller" \
  --set manager.image.repository="${HARBOR_REGISTRY}/neuvector/neuvector/manager" \
  --set cve.scanner.image.repository="${HARBOR_REGISTRY}/neuvector/neuvector/scanner" \
  --set cve.updater.image.repository="${HARBOR_REGISTRY}/neuvector/neuvector/updater" \
  --set enforcer.image.repository="${HARBOR_REGISTRY}/neuvector/neuvector/enforcer"

kubectl -n cattle-neuvector-system rollout status deploy/neuvector-manager-pod

# ---------------------------------------------------------------------------
# Ingress for NeuVector Manager UI
# ---------------------------------------------------------------------------
cat << 'EOF' > /tmp/neuvector-ingress.yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neuvector-manager
  namespace: cattle-neuvector-system
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: neuvector.applications.enclave.kubernerdes.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: neuvector-service-webui
                port:
                  number: 8443
  tls:
    - hosts:
        - neuvector.applications.enclave.kubernerdes.com
EOF
kubectl apply -f /tmp/neuvector-ingress.yaml
kubectl get ingress -n cattle-neuvector-system

# ---------------------------------------------------------------------------
# Retrieve bootstrap password
# ---------------------------------------------------------------------------
echo "NeuVector UI: https://neuvector.applications.enclave.kubernerdes.com"
echo "Bootstrap password: $(kubectl get secret \
  --namespace cattle-neuvector-system neuvector-bootstrap-secret \
  -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ "\n" }}' 2>/dev/null \
  || echo '(not yet available — check after pods are fully ready)')"

exit 0
