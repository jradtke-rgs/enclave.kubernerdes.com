# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-)

# Reference: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/kubernetes-cluster-setup/rke2-for-rancher
# Reference: https://docs.rke2.io/install/quickstart

# ssh-key for rancher should exist (if you deployed VM on Harvester)

# SU to root
sudo su -

sed -i -e '/observability/d' /etc/hosts

case $(uname -n) in 
  # *************************
  ## RANCHER CLUSTER
  # *************************
  rancher-0*)
cat << EOF | tee ~/.rancher.vars
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_INSTALL_CHANNEL=v1.34
export MY_RKE2_TOKEN=WaggonerRancher
export MY_RKE2_ENDPOINT=10.10.12.210
export MY_RKE2_HOSTNAME=rancher.enclave.kubernerdes.com
EOF
source ~/.rancher.vars

# Remove any existing host entry
# Add all the Rancher Nodes to /etc/hosts
sed -i -e '/rancher/d' /etc/hosts
cat << EOF | tee -a  /etc/hosts

# rancher nodes
10.10.12.211    rancher-01.enclave.kubernerdes.com rancher-01
10.10.12.212    rancher-02.enclave.kubernerdes.com rancher-02
10.10.12.213    rancher-03.enclave.kubernerdes.com rancher-03
EOF
  ;; 
  # *************************
  ## OBSERVABILITY CLUSTER 
  # *************************
  observability-0*)
cat << EOF | tee ~/.rancher.vars
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_INSTALL_CHANNEL=v1.34
export MY_RKE2_TOKEN=WaggonerObservability
export MY_RKE2_ENDPOINT=10.10.12.220
export MY_RKE2_HOSTNAME=observability.enclave.kubernerdes.com
EOF
source ~/.rancher.vars

cat << EOF | tee -a  /etc/hosts

# observability nodes
10.10.12.221    observability-01.enclave.kubernerdes.com observability-01
10.10.12.222    observability-02.enclave.kubernerdes.com observability-02
10.10.12.223    observability-03.enclave.kubernerdes.com observability-03
EOF

  ;;
esac

# Make sure the proxy allows ports 6443 and 9345
# 6443 = Kubernetes API
# 9345 = RKE2 supervisor/node registration
# TODO write a test for this?

# Create the RKE2 config directory
mkdir -p /etc/rancher/rke2

# Write the RKE2 config file
case $(uname -n) in
  rancher-01|observability-01)
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
  rancher-01|observability-01)
    echo "Now installing first RKE2 node"
  ;;
  *)
    SLEEPY_TIME=$(shuf -i 30-45 -n 1)
    sleep $SLEEPY_TIME 
  ;;
esac
curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=${MY_RKE2_INSTALL_CHANNEL} sh -
echo "export PATH=\$PATH:/opt/rke2/bin" >> ~/.bashrc

# Enable and start the rke2-server service
case $(uname -n) in
  rancher-01|observability-01) systemctl enable rke2-server.service --now ;;
  *)
    SLEEPY_TIME=$(shuf -i 30-45 -n 1)
    sleep $SLEEPY_TIME # allow time for the first node to complete install
    systemctl enable rke2-server.service --now
  ;;
esac

. /etc/*release*
case $NAME in
  SL-Micro)
    case $(uname -n) in
      rancher-01|observability-01)  SLEEPY_TIME=5; sleep $SLEEPY_TIME ;;
      *) SLEEPY_TIME=$(shuf -i 30-45 -n 1;) sleep $SLEEPY_TIME ;;
    esac
    echo "Shutting down to ensure transactional update is committed" && shutdown now -r
  ;;
esac

exit 0
