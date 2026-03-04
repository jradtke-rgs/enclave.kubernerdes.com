# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-)

# Reference: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/rke2-for-rancher
# Reference: https://docs.rke2.io/install/quickstart

# Create 2 x VM with (4 vCPU, 16GB, 50GB HDD)
# Install SL-micro 6.1
# open SSH port

# ssh-key for rancher should exist (if you deployed VM on Harvester)

## RANCHER
# Run this from kubernerd
scp sles@rancher-01:.kube/config ~/.kube/enclave-rancher.kubeconfig
export KUBECONFIG=~/.kube/enclave-rancher.kubeconfig

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

kubectl create namespace cattle-system

CERTMGR_VERSION=v1.18.0
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERTMGR_VERSION}/cert-manager.crds.yaml

helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace

helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --set hostname=rancher.enclave.kubernerdes.com \
  --set replicas=3 \
  --set bootstrapPassword=Passw0rd01

echo https://rancher.enclave.kubernerdes.com/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')
BOOTSTRAP_PASSWORD=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}')

exit 0

