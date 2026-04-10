#!/bin/bash
set -euo pipefail

# install_RKE2.sh — Install RKE2 on a cluster node (airgap via Harbor)
#
# Run as root (sudo su -) on each node.
#   sudo -i bash ~sles/install_RKE2.sh
#
# Used for: rancher cluster, observability cluster, apps cluster
# Node-aware: *-01 is genesis; subsequent nodes wait and join.
#
# KEY DIFFERENCE FROM COMMUNITY INSTALL:
#   - Install script fetched from hauler fileserver (not get.rke2.io)
#   - Container images pulled from Harbor (harbor.enclave.kubernerdes.com/rke2)
#   - system-default-registry redirects all cluster image pulls to Harbor/rke2 project
#   - Enclave root CA must be trusted on each node before rke2-server starts
#
# SL-Micro nodes:
#   After rke2-server starts, this script installs a systemd one-shot
#   (rke2-postboot.service) to set up kubeconfig after the mandatory reboot.
#   On non-SL-Micro nodes the kubeconfig setup runs inline.
#
# Node hostnames should be SHORT names (e.g. rancher-01, not FQDN).
#   hostnamectl set-hostname rancher-01
#
# Manual fallback if the one-shot fails:
#   Run Scripts/install_RKE2_postboot.sh after the node comes back up.

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

HARBOR_REGISTRY="harbor.enclave.kubernerdes.com"
HAULER_FILESERVER="http://10.10.12.10:8080"

# ---------------------------------------------------------------------------
# Set cluster-specific variables
# ---------------------------------------------------------------------------
case $(hostname -s) in
  rancher-0*)
    cat << 'EOF' | tee /root/.rke2.vars
export MY_CLUSTER=rancher
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_TOKEN=ChangeMe-RancherRKE2
export MY_RKE2_VIP=10.10.12.210
export MY_RKE2_HOSTNAME=rancher.enclave.kubernerdes.com
EOF
  ;;
  observability-0*)
    cat << 'EOF' | tee /root/.rke2.vars
export MY_CLUSTER=observability
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_TOKEN=ChangeMe-ObsRKE2
export MY_RKE2_VIP=10.10.12.220
export MY_RKE2_HOSTNAME=observability.enclave.kubernerdes.com
EOF
  ;;
  apps-0*)
    cat << 'EOF' | tee /root/.rke2.vars
export MY_CLUSTER=apps
export MY_RKE2_VERSION=v1.34.4+rke2r1
export MY_RKE2_TOKEN=ChangeMe-AppsRKE2
export MY_RKE2_VIP=10.10.12.230
export MY_RKE2_HOSTNAME=apps.enclave.kubernerdes.com
EOF
  ;;
  *)
    echo "ERROR: Unrecognised hostname '$(hostname -s)'. Add a case block for this cluster."
    exit 1
  ;;
esac

source /root/.rke2.vars

# ---------------------------------------------------------------------------
# /etc/hosts — static cluster node entries (no DNS dependency at install time)
# ---------------------------------------------------------------------------
sed -i -e "/${MY_CLUSTER}/d" /etc/hosts
case ${MY_CLUSTER} in
  rancher)
    cat << EOF >> /etc/hosts
10.10.12.211    rancher-01.enclave.kubernerdes.com rancher-01
10.10.12.212    rancher-02.enclave.kubernerdes.com rancher-02
10.10.12.213    rancher-03.enclave.kubernerdes.com rancher-03
EOF
  ;;
  observability)
    cat << EOF >> /etc/hosts
10.10.12.221    observability-01.enclave.kubernerdes.com observability-01
10.10.12.222    observability-02.enclave.kubernerdes.com observability-02
10.10.12.223    observability-03.enclave.kubernerdes.com observability-03
EOF
  ;;
  apps)
    cat << EOF >> /etc/hosts
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

case $(hostname -s) in
  *-01)
    cat << EOF > /etc/rancher/rke2/config.yaml
token: ${MY_RKE2_TOKEN}
system-default-registry: ${HARBOR_REGISTRY}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
  *)
    cat << EOF > /etc/rancher/rke2/config.yaml
server: https://${MY_RKE2_VIP}:9345
token: ${MY_RKE2_TOKEN}
system-default-registry: ${HARBOR_REGISTRY}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
esac

# ---------------------------------------------------------------------------
# Enclave root CA — must be trusted before rke2-server starts so containerd
# can verify Harbor's TLS certificate.
# ---------------------------------------------------------------------------
curl -sfL "${HAULER_FILESERVER}/enclave-root-ca.crt" \
  -o /etc/pki/trust/anchors/enclave-root-ca.crt
update-ca-certificates

# ---------------------------------------------------------------------------
# registries.yaml — must be in place BEFORE rke2-server starts.
#
# system-default-registry must be a plain hostname (RFC 3986 URI authority).
# RKE2 bootstrap pulls images as: {registry}/{original-image-name}, so Harbor
# must have images at harbor.enclave.kubernerdes.com/rancher/rke2-runtime (no
# project prefix) — see 01_hauler_sync.sh for correct push target.
#
# The rewrite rule handles images that containerd pulls AFTER bootstrap
# (e.g. CNI, kube-proxy). The bootstrap image pull (rke2-runtime) bypasses
# registries.yaml entirely — it uses RKE2's own HTTP client.
# ---------------------------------------------------------------------------
cat << EOF > /etc/rancher/rke2/registries.yaml
mirrors:
  "harbor.enclave.kubernerdes.com":
    endpoint:
      - "https://harbor.enclave.kubernerdes.com"
configs:
  "harbor.enclave.kubernerdes.com":
    auth:
      username: admin
      password: ${GENERIC_PASSWORD}
    tls:
      ca_file: /etc/pki/trust/anchors/enclave-root-ca.crt
EOF

# ---------------------------------------------------------------------------
# Install RKE2 — from hauler fileserver (airgap), pinned version
# ---------------------------------------------------------------------------
case $(hostname -s) in
  *-01) echo "==> Genesis node — installing immediately" ;;
  *)
    SLEEPY_TIME=$(shuf -i 45-90 -n 1)
    echo "==> Worker node — waiting ${SLEEPY_TIME}s before install..."
    sleep "${SLEEPY_TIME}"
  ;;
esac

curl -sfL "${HAULER_FILESERVER}/install-rke2.sh" \
  | INSTALL_RKE2_VERSION="${MY_RKE2_VERSION}" sh -

# PATH additions for RKE2 binaries
RKE2_PATH='export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin'
grep -qxF "${RKE2_PATH}" /root/.bashrc || echo "${RKE2_PATH}" >> /root/.bashrc
grep -qxF "${RKE2_PATH}" ~sles/.bashrc 2>/dev/null \
  || echo "${RKE2_PATH}" >> ~sles/.bashrc 2>/dev/null || true
export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin

# ---------------------------------------------------------------------------
# Enable and start RKE2
# ---------------------------------------------------------------------------
case $(hostname -s) in
  *-01) echo "==> Starting rke2-server (genesis)" ;;
  *)
    SLEEPY_TIME=$(shuf -i 45-90 -n 1)
    echo "==> Waiting ${SLEEPY_TIME}s for genesis node to be ready..."
    sleep "${SLEEPY_TIME}"
  ;;
esac

systemctl enable rke2-server.service --now

# ---------------------------------------------------------------------------
# Post-install kubeconfig setup
#
# SL-Micro: copy the postboot script to /var (survives snapshot reboot) and
#           reboot. After reboot run install_RKE2_postboot.sh manually if it
#           did not run automatically.
# Other:    run the postboot script inline — no reboot needed.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POSTBOOT_SCRIPT="${SCRIPT_DIR}/install_RKE2_postboot.sh"

. /etc/*release* 2>/dev/null || true
case ${NAME:-} in
  SL-Micro)
    echo "==> SL-Micro detected — copying postboot script and rebooting"
    cp "${POSTBOOT_SCRIPT}" /var/lib/install_RKE2_postboot.sh
    chmod 0700 /var/lib/install_RKE2_postboot.sh

    echo "==> After reboot, run: sudo bash /var/lib/install_RKE2_postboot.sh"
    echo "==> Rebooting to commit transactional update..."
    case $(hostname -s) in
      *-01) sleep 5 ;;
      *)    sleep $(shuf -i 30-45 -n 1) ;;
    esac
    shutdown -r now
  ;;
  *)
    bash "${POSTBOOT_SCRIPT}"
  ;;
esac
