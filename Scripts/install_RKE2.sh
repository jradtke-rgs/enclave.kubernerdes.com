#!/bin/bash
set -euo pipefail

# install_RKE2.sh — Install RKE2 on a cluster node (direct from Carbide registry)
#
# TWO MODES:
#
# 1. Orchestrator (run from nuc-00 as mansible):
#      bash install_RKE2.sh <rancher|observability|apps>
#    Copies Scripts/ and ~/.bashrc.d/RGS to each node as sles, then fires
#    the install on all three nodes in parallel via SSH.
#
# 2. Node install (run on the node itself as root):
#      sudo -i bash ~sles/Scripts/install_RKE2.sh
#    Detected automatically when hostname matches a cluster node pattern.
#
# Used for: rancher cluster, observability cluster, apps cluster
# Node-aware: *-01 is genesis; subsequent nodes wait and join.
#
# Carbide hardened images are pulled directly from rgcrprod.azurecr.us.
# Credentials must be in ~/.bashrc.d/RGS (Carbide_Registry_Username / Carbide_Registry_Password).
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

# ---------------------------------------------------------------------------
# ORCHESTRATOR MODE — runs from nuc-00, hostname does not match a cluster node
# ---------------------------------------------------------------------------
case $(hostname -s) in
  rancher-0*|observability-0*|apps-0*)
    : # node install mode — continue below
    ;;
  *)
    CLUSTER="${1:-}"
    if [[ -z "${CLUSTER}" ]]; then
      echo "Usage: $0 <rancher|observability|apps>"
      exit 1
    fi

    case "${CLUSTER}" in
      rancher)        NODES=(rancher-01 rancher-02 rancher-03) ;;
      observability)  NODES=(observability-01 observability-02 observability-03) ;;
      apps)           NODES=(apps-01 apps-02 apps-03) ;;
      *)
        echo "ERROR: Unknown cluster '${CLUSTER}'. Use: rancher, observability, or apps."
        exit 1
        ;;
    esac

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    RGS_CREDS="${HOME}/.bashrc.d/RGS"

    if [[ ! -f "${RGS_CREDS}" ]]; then
      echo "ERROR: ${RGS_CREDS} not found. Cannot copy Carbide credentials to nodes."
      exit 1
    fi

    echo "==> Copying scripts and credentials to ${CLUSTER} nodes"
    for NODE in "${NODES[@]}"; do
      echo "    ${NODE}: copying Scripts/ and .bashrc.d/RGS"
      ssh "sles@${NODE}" "mkdir -p ~/Scripts ~/.bashrc.d"
      scp "${SCRIPT_DIR}/install_RKE2.sh" \
          "${SCRIPT_DIR}/install_RKE2_postboot.sh" \
          "sles@${NODE}:~/Scripts/"
      scp "${RGS_CREDS}" "sles@${NODE}:~/.bashrc.d/RGS"
    done

    echo "==> Firing install on all nodes in parallel"
    for NODE in "${NODES[@]}"; do
      echo "    ${NODE}: starting install"
      ssh "sles@${NODE}" "sudo -i bash ~sles/Scripts/install_RKE2.sh" &
    done

    echo "==> Waiting for all nodes to complete..."
    wait
    echo "==> Done. Check each node for errors."
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# NODE INSTALL MODE — must be root
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

# Source Carbide credentials — prefer the invoking user's home when run via sudo
RGS_CREDS="${HOME}/.bashrc.d/RGS"
if [[ -n "${SUDO_USER:-}" ]]; then
  _USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
  RGS_CREDS="${_USER_HOME}/.bashrc.d/RGS"
fi
set +u
[[ -f "${RGS_CREDS}" ]] && source "${RGS_CREDS}" || true
set -u

if [[ -z "${Carbide_Registry_Username:-}" || -z "${Carbide_Registry_Password:-}" ]]; then
  echo "ERROR: Carbide credentials not set. Ensure ~/.bashrc.d/RGS is populated for user ${SUDO_USER:-root}."
  exit 1
fi

CARBIDE_REGISTRY="rgcrprod.azurecr.us"

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
system-default-registry: ${CARBIDE_REGISTRY}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
  *)
    cat << EOF > /etc/rancher/rke2/config.yaml
server: https://${MY_RKE2_VIP}:9345
token: ${MY_RKE2_TOKEN}
system-default-registry: ${CARBIDE_REGISTRY}
tls-san:
  - ${MY_RKE2_VIP}
  - ${MY_RKE2_HOSTNAME}
EOF
  ;;
esac

# ---------------------------------------------------------------------------
# registries.yaml — must be in place BEFORE rke2-server starts.
#
# Provides auth for the Carbide registry so containerd can pull hardened
# images during bootstrap and normal cluster operation.
# ---------------------------------------------------------------------------
cat << EOF > /etc/rancher/rke2/registries.yaml
configs:
  "${CARBIDE_REGISTRY}":
    auth:
      username: ${Carbide_Registry_Username}
      password: ${Carbide_Registry_Password}
EOF

# ---------------------------------------------------------------------------
# Install RKE2 — from get.rke2.io, pinned version
# ---------------------------------------------------------------------------
case $(hostname -s) in
  *-01) echo "==> Genesis node — installing immediately" ;;
  *)
    SLEEPY_TIME=$(shuf -i 45-90 -n 1)
    echo "==> Worker node — waiting ${SLEEPY_TIME}s before install..."
    sleep "${SLEEPY_TIME}"
  ;;
esac

curl -sfL https://get.rke2.io \
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
