# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-_
# Reference: https://observabilitymanager.docs.observability.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/k3s-for-observability

# Create 2 x VM with (4 vCPU, 16GB, 50GB HDD)
# Install SL-micro 6.x
# open SSH port

# ssh-key for observability should exist (if you deployed VM on Harvester)

# SU to root
sudo su -

# Add all the Observability Nodes to /etc/hosts
cat << EOF | tee -a  /etc/hosts

# Observability Nodes
10.10.12.221    observability-01.enclave.kubernerdes.com observability-01
10.10.12.222    observability-02.enclave.kubernerdes.com observability-02
10.10.12.223    observability-03.enclave.kubernerdes.com observability-03
EOF

# Set some variables
export MY_K3S_VERSION=v1.34.4+k3s1
export MY_K3S_INSTALL_CHANNEL=v1.34
export MY_K3S_TOKEN=CattleDrive
export MY_K3S_ENDPOINT=10.10.12.220
export MY_K3S_HOSTNAME=observability.enclave.kubernerdes.com

# Make sure the proxy allows port 6443
# TODO write a test for this?

# Run the install process
SLEEPY_TIME=$(shuf -i 60-90 -n 1)

#  THE POINT OF THIS SECTION IS TO:
#   First install K3s on node-01, and with a random delay install on node-02 and node-03.
#   Then reboot each node at staggered periods
case $(uname -n) in
  observability-01)
    echo "curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${MY_K3S_INSTALL_CHANNEL} sh -s - server --cluster-init --token ${MY_K3S_TOKEN} --tls-san ${MY_K3S_ENDPOINT},${MY_K3S_HOSTNAME}"
    curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${MY_K3S_INSTALL_CHANNEL} sh -s - server --cluster-init --token ${MY_K3S_TOKEN} --tls-san ${MY_K3S_ENDPOINT},${MY_K3S_HOSTNAME}
  ;;
  *)
    sleep $SLEEPY_TIME # allow time for the first node to complete install
    echo "curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${MY_K3S_INSTALL_CHANNEL} sh -s - --server https://${MY_K3S_ENDPOINT}:6443 --token ${MY_K3S_TOKEN}"
    curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=${MY_K3S_INSTALL_CHANNEL} sh -s - --server https://${MY_K3S_ENDPOINT}:6443 --token ${MY_K3S_TOKEN}
  ;;
esac

. /etc/*release*
SLEEPY_TIME=$(shuf -i 5-11 -n 1)
case $NAME in 
  SL-Micro)
    echo "Shutting down to ensure transactional update is committed"
    sleep $SLEEPY_TIME
    shutdown now -r
  ;;
esac

# This needs to be done after the restart (apparently)
# Make a copy of the KUBECONFIG for non-root use
# TODO:  I need to 1/ decide if this script should run as root (probably: yes) 2/ figure out what user to store the kubeconfig with (probably: sles)
mkdir ~/.kube; sudo cp $(find /etc -name k3s.yaml) ~/.kube/config; sudo chown $(whoami) ~/.kube/config
mkdir ~sles/.kube; sudo cp $(find /etc -name k3s.yaml) ~sles/.kube/config; sudo chown -R sles ~sles/.kube/config
export KUBECONFIG=~/.kube/config
openssl s_client -connect 127.0.0.1:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.0
grep DNS cert.0
kubectl get nodes

# Replace localhost IP with the HAproxy endpoint
## TODO: need to make this actually work
. ./env.vars
sed -i -e "s/127.0.0.1/${MY_K3S_ENDPOINT}/g" $KUBECONFIG
openssl s_client -connect 127.0.0.1:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.1
kubectl get nodes

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

# Create ingress using traefik for O11y
cat << EOF > suse-observability-ingress.yaml
---
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
