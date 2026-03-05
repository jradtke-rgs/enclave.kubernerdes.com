# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-_
# Reference: https://observabilitymanager.docs.observability.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/k3s-for-observability

scp 10.10.12.221:.kube/config .kube/enclave-observability.kubeconfig
echo "Note: you should update the cluster: name: value"
export KUBECONFIG=~/.kube/enclave-observability.kubeconfig
chmod 0664 $KUBECONFIG
scp $KUBECONFIG 10.10.12.10:/srv/www/.kube/

#######################################
# Install Local Path Provisioner for Storage
#######################################
# NOTE: The RKE2 VM disks are already backed by Harvester Longhorn (replica=3),
#       so we use local-path-provisioner to avoid redundant replication.
#       Do NOT install standalone Longhorn or the Harvester CSI driver here.
LOCAL_PATH_VERSION=v0.0.30
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/${LOCAL_PATH_VERSION}/deploy/local-path-storage.yaml
kubectl wait --for=condition=available deployment/local-path-provisioner -n local-path-storage --timeout=60s

# Set local-path as the default StorageClass
kubectl patch sc local-path -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Verify
kubectl get sc

#######################################
# Install Cert Manager
#######################################
CERTMGR_VERSION=v1.18.0
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update

#######################################
# Install SUSE Observability
#######################################
echo "Installing SUSE Observability (StackState)..."

# I do this in a separate/well-known directory - not necessary
mkdir -p ~/Developer/Projects/observability.enclave.kubernerdes.com; cd $_

# Add the SUSE Observability Helm Repo
helm repo add suse-observability https://charts.rancher.com/server-charts/prime/suse-observability
helm repo update

# Create template files
export VALUES_DIR=.
helm template \
  --set license='$O11Y_LICENSE' \
  --set rancherUrl='https://rancher.enclave.kubernerdes.com' \
  --set baseUrl='https://observability.enclave.kubernerdes.com' \
  --set sizing.profile='10-nonha' \
  suse-observability-values \
  suse-observability/suse-observability-values --output-dir $VALUES_DIR

# Install using temmplate files created in previous step
helm upgrade --install \
    --namespace suse-observability \
    --create-namespace \
    --values $VALUES_DIR/suse-observability-values/templates/baseConfig_values.yaml \
    --values $VALUES_DIR/suse-observability-values/templates/sizing_values.yaml \
    --values $VALUES_DIR/suse-observability-values/templates/affinity_values.yaml \
    suse-observability \
    suse-observability/suse-observability

kubectl get all -n suse-observability
grep 'admin password' $(find $HOME -name baseConfig_values.yaml)

# Create ingress using traefik for O11y (for K3s)
cat << EOF > suse-observability-ingress.yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: suse-observability-ui
  namespace: suse-observability
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
spec:
  ingressClassName: traefik
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
kubectl apply -f ./suse-observability-ingress.yaml

# Create ingress using traefik for O11y (for RKE2)
cat << EOF > suse-observability-ingress.yaml
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
EOF
kubectl apply -f ./suse-observability-ingress.yaml

exit 0
