# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-_
# Reference: https://observabilitymanager.docs.observability.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/k3s-for-observability

# you need to retrieve the KUBECONFIG from Rancher Manager
# save it as ~/.kube/enclave-observability.kubeconfig
chmod 0664 $KUBECONFIG
export KUBECONFIG=~/.kube/enclave-observability.kubeconfig
scp $KUBECONFIG 10.10.12.10:/srv/www/.kube/

#######################################
# Install Cert Manager
#######################################
CERTMGR_VERSION=v1.19.4
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update

#######################################
# Install SUSE Observability
#######################################
echo "Installing SUSE Observability (StackState)..."

# I do this in a separate/well-known directory - not necessary
mv ~/Developer/Projects/observability.enclave.kubernerdes.com ~/Developer/Projects/observability.enclave.kubernerdes.com-$(date +%F)
mkdir -p ~/Developer/Projects/observability.enclave.kubernerdes.com; cd $_

# Add the SUSE Observability Helm Repo
helm repo add suse-observability https://charts.rancher.com/server-charts/prime/suse-observability
helm repo update

# Create template files
export VALUES_DIR=.
helm template \
  --set license="$O11Y_LICENSE" \
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

echo "Note: you are going to see a LOT of scary warnings while things spin up.  You can likely ignore them.
echo "      This will take 15-20 minutes before things are working and stabilized"
kubectl get pods -n suse-observability -w

grep 'admin password' $(find $HOME -name baseConfig_values.yaml)

# Create ingress using traefik for O11y (for K3s or RKE2)
case $(kubectl version -o json | jq -r '.serverVersion.gitVersion') in 
  *k3s*)
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
  ;;
  *rke2*)
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
  ;;
esac
kubectl apply -f ./suse-observability-ingress.yaml

exit 0
