# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-)

# Reference: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/rke2-for-rancher
# Reference: https://docs.rke2.io/install/quickstart

# Create 2 x VM with (4 vCPU, 16GB, 50GB HDD)
# Install SL-micro 6.1
# open SSH port

# ssh-key for rancher should exist (if you deployed VM on Harvester)

# SU to root
sudo su -

# Remove any existing host entry
sudo sed -i -e '/rancher/d' /etc/hosts
# Add all the Rancher Nodes to /etc/hosts
cat << EOF | tee -a  /etc/hosts

# Rancher Nodes
10.10.12.211    rancher-01.enclave.kubernerdes.com rancher-01
10.10.12.212    rancher-02.enclave.kubernerdes.com rancher-02
10.10.12.213    rancher-03.enclave.kubernerdes.com rancher-03
EOF

# Set some variables
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_INSTALL_CHANNEL=v1.34
export MY_RKE2_TOKEN=Waggoner
export MY_RKE2_ENDPOINT=10.10.12.210
export MY_RKE2_HOSTNAME=rancher.enclave.kubernerdes.com

# Make sure the proxy allows ports 6443 and 9345
# 6443 = Kubernetes API
# 9345 = RKE2 supervisor/node registration
# TODO write a test for this?

# Create the RKE2 config directory
mkdir -p /etc/rancher/rke2

# Write the RKE2 config file
case $(uname -n) in
  rancher-01)
    cat << EOF > /etc/rancher/rke2/config.yaml
token: ${MY_RKE2_TOKEN}
tls-san:
  - ${MY_RKE2_ENDPOINT}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
  *)
    cat << EOF > /etc/rancher/rke2/config.yaml
server: https://${MY_RKE2_ENDPOINT}:9345
token: ${MY_RKE2_TOKEN}
tls-san:
  - ${MY_RKE2_ENDPOINT}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
esac

# Run the install process
# TODO: set the sleep duration to a variable between 30 and 45
case $(uname -n) in
  rancher-01)
    echo "Now installing first RKE2 node"
  ;;
  *)
    SLEEPY_TIME=$(shuf -i 30-45 -n 1)
    sleep $SLEEPY_TIME 
  ;;
esac
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=${MY_RKE2_INSTALL_CHANNEL} sh -

# Enable and start the rke2-server service
case $(uname -n) in
  rancher-01)
    systemctl enable rke2-server.service --now
  ;;
  *)
    sleep 120 # allow time for the first node to complete install
    systemctl enable rke2-server.service --now
  ;;
esac

. /etc/*release*
case $NAME in
  SL-Micro)
    case $(uname -n) in
      rancher-01)  SLEEPY_TIME=5; sleep $SLEEPY_TIME ;;
      *) SLEEPY_TIME=$(shuf -i 30-45 -n 1;) sleep $SLEEPY_TIME ;;
    esac
    echo "Shutting down to ensure transactional update is committed" && shutdown now -r
  ;;
esac

## RECONNECT TO NODES via ssh

# This needs to be done after the restart (apparently)
# Add RKE2 binaries to PATH (kubectl, crictl, etc.)
export PATH=$PATH:/var/lib/rancher/rke2/bin
echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> ~/.bashrc

# Make a copy of the KUBECONFIG for non-root use
# TODO:  I need to 1/ decide if this script should run as root (probably: yes), figure out what user to store the kubeconfig with (probably: sles)
mkdir ~/.kube; sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config; sudo chown $(whoami) ~/.kube/config
mkdir ~sles/.kube; sudo cp /etc/rancher/rke2/rke2.yaml ~sles/.kube/config; sudo chown -R sles ~sles/.kube/
export KUBECONFIG=~/.kube/config
openssl s_client -connect 127.0.0.1:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.0
grep DNS cert.0
kubectl get nodes

# Replace localhost IP with the HAproxy endpoint
sed -i -e "s/127.0.0.1/${MY_RKE2_ENDPOINT}/g" $KUBECONFIG
openssl s_client -connect 127.0.0.1:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.1
kubectl get nodes

## RANCHER
# Run this from kubernerd
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

