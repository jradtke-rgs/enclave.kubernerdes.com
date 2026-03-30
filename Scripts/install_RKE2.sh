# install_RKE2.sh — Install RKE2 on a cluster node (airgap from hauler)
#
# Not intended to be run as a script — cut and paste sections as needed.
# Run as root (sudo su -) on each node.
#
# Used for: rancher cluster, observability cluster, apps cluster
# Node-aware: *-01 is genesis; subsequent nodes wait and join.
#
# KEY DIFFERENCE FROM COMMUNITY INSTALL:
#   - Install script fetched from hauler fileserver (not get.rke2.io)
#   - Container images pulled from hauler registry (not registry.rancher.com)
#   - system-default-registry redirects all cluster image pulls to internal registry

INTERNAL_REGISTRY="10.10.12.10:5000"
HAULER_FILESERVER="http://10.10.12.10:8080"

# ---------------------------------------------------------------------------
# Set cluster-specific variables — run this block on ALL nodes in the cluster
# Edit for each cluster: rancher / observability / apps
# ---------------------------------------------------------------------------
case $(uname -n) in
  rancher-0*)
    cat << 'EOF' | tee ~/.rke2.vars
export MY_CLUSTER=rancher
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_TOKEN=ChangeMe-RancherRKE2
export MY_RKE2_VIP=10.10.12.210
export MY_RKE2_HOSTNAME=rancher.enclave.kubernerdes.com
EOF
  ;;
  observability-0*)
    cat << 'EOF' | tee ~/.rke2.vars
export MY_CLUSTER=observability
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_TOKEN=ChangeMe-ObsRKE2
export MY_RKE2_VIP=10.10.12.220
export MY_RKE2_HOSTNAME=observability.enclave.kubernerdes.com
EOF
  ;;
  apps-0*)
    cat << 'EOF' | tee ~/.rke2.vars
export MY_CLUSTER=apps
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_TOKEN=ChangeMe-AppsRKE2
export MY_RKE2_VIP=10.10.12.230
export MY_RKE2_HOSTNAME=apps.enclave.kubernerdes.com
EOF
  ;;
esac
source ~/.rke2.vars

# ---------------------------------------------------------------------------
# /etc/hosts — add cluster nodes (static, no dependency on DNS at install time)
# ---------------------------------------------------------------------------
sed -i -e "/${MY_CLUSTER}/d" /etc/hosts
case ${MY_CLUSTER} in
  rancher)
    cat << EOF | tee -a /etc/hosts
10.10.12.211    rancher-01.enclave.kubernerdes.com rancher-01
10.10.12.212    rancher-02.enclave.kubernerdes.com rancher-02
10.10.12.213    rancher-03.enclave.kubernerdes.com rancher-03
EOF
  ;;
  observability)
    cat << EOF | tee -a /etc/hosts
10.10.12.221    observability-01.enclave.kubernerdes.com observability-01
10.10.12.222    observability-02.enclave.kubernerdes.com observability-02
10.10.12.223    observability-03.enclave.kubernerdes.com observability-03
EOF
  ;;
  apps)
    cat << EOF | tee -a /etc/hosts
10.10.12.231    apps-01.enclave.kubernerdes.com apps-01
10.10.12.232    apps-02.enclave.kubernerdes.com apps-02
10.10.12.233    apps-03.enclave.kubernerdes.com apps-03
EOF
  ;;
esac

# ---------------------------------------------------------------------------
# RKE2 config
# ---------------------------------------------------------------------------
mkdir -p /etc/rancher/rke2

case $(uname -n) in
  *-01)
    cat << EOF > /etc/rancher/rke2/config.yaml
token: ${MY_RKE2_TOKEN}
system-default-registry: ${INTERNAL_REGISTRY}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
  *)
    cat << EOF > /etc/rancher/rke2/config.yaml
server: https://${MY_RKE2_VIP}:9345
token: ${MY_RKE2_TOKEN}
system-default-registry: ${INTERNAL_REGISTRY}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
esac

# ---------------------------------------------------------------------------
# registries.yaml — tell RKE2 to use plain HTTP for internal registry
# Must be in place BEFORE rke2-server starts or it will try HTTPS and fail.
# ---------------------------------------------------------------------------
cat << EOF > /etc/rancher/rke2/registries.yaml
mirrors:
  "${INTERNAL_REGISTRY}":
    endpoint:
      - "http://${INTERNAL_REGISTRY}"
EOF

# ---------------------------------------------------------------------------
# Install RKE2 — from hauler fileserver (airgap), pinned version
# ---------------------------------------------------------------------------
case $(uname -n) in
  *-01) echo "Installing genesis node (no delay)" ;;
  *)
    SLEEPY_TIME=$(shuf -i 45-90 -n 1)
    echo "Waiting ${SLEEPY_TIME}s before joining..."
    sleep ${SLEEPY_TIME}
  ;;
esac

curl -sfL ${HAULER_FILESERVER}/install-rke2.sh \
  | INSTALL_RKE2_VERSION=${MY_RKE2_VERSION} sh -

# PATH additions for RKE2 binaries
echo 'export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin' >> ~/.bashrc
echo 'export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin' >> ~sles/.bashrc 2>/dev/null || true

# ---------------------------------------------------------------------------
# Enable and start RKE2
# ---------------------------------------------------------------------------
case $(uname -n) in
  *-01) systemctl enable rke2-server.service --now ;;
  *)
    SLEEPY_TIME=$(shuf -i 45-90 -n 1)
    echo "Waiting ${SLEEPY_TIME}s for genesis node to be ready..."
    sleep ${SLEEPY_TIME}
    systemctl enable rke2-server.service --now
  ;;
esac

# SL-Micro requires a reboot to commit the transactional update
. /etc/*release* 2>/dev/null || true
case ${NAME:-} in
  SL-Micro)
    echo "SL-Micro detected — rebooting to commit transactional update"
    case $(uname -n) in
      *-01) sleep 5 ;;
      *)    sleep $(shuf -i 30-45 -n 1) ;;
    esac
    shutdown -r now
  ;;
esac

# ---------------------------------------------------------------------------
# Post-install — kubeconfig
# ---------------------------------------------------------------------------
mkdir -p ~/.kube
sudo cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
sudo chown $(whoami) ~/.kube/config

mkdir -p ~sles/.kube 2>/dev/null || true
sudo cp ~/.kube/config ~sles/.kube/config 2>/dev/null || true
sudo chown -R sles ~sles/.kube/ 2>/dev/null || true

# Point kubeconfig at VIP instead of 127.0.0.1
sed -i -e "s/127.0.0.1/${MY_RKE2_VIP}/g" ~/.kube/config

export KUBECONFIG=~/.kube/config
kubectl get nodes

exit 0
