#!/bin/bash
set -euo pipefail

# install_RKE2_postboot.sh — Run once after RKE2 server starts on SL-Micro
#
# TWO MODES:
#
# 1. Orchestrator (run from nuc-00 as mansible):
#      bash install_RKE2_postboot.sh <rancher|observability|apps>
#    Runs postboot on all nodes in parallel, then fetches the kubeconfig
#    from the genesis node to ~/.kube/enclave-<cluster>.kubeconfig on nuc-00.
#
# 2. Node (run on the node itself as root):
#      sudo -i bash ~sles/Scripts/install_RKE2_postboot.sh
#    Detected automatically when hostname matches a cluster node pattern.
#    Also runs automatically via install_RKE2.sh on non-SL-Micro nodes.
#    Manual fallback: sudo bash /var/lib/install_RKE2_postboot.sh

# ---------------------------------------------------------------------------
# ORCHESTRATOR MODE — runs from nuc-00, hostname does not match a cluster node
# ---------------------------------------------------------------------------
case $(hostname -s) in
  rancher-0*|observability-0*|apps-0*)
    : # node mode — continue below
    ;;
  *)
    CLUSTER="${1:-}"
    if [[ -z "${CLUSTER}" ]]; then
      echo "Usage: $0 <rancher|observability|apps>"
      exit 1
    fi

    case "${CLUSTER}" in
      rancher)        NODES=(rancher-01 rancher-02 rancher-03);       GENESIS=rancher-01 ;;
      observability)  NODES=(observability-01 observability-02 observability-03); GENESIS=observability-01 ;;
      apps)           NODES=(apps-01 apps-02 apps-03);                GENESIS=apps-01 ;;
      *)
        echo "ERROR: Unknown cluster '${CLUSTER}'. Use: rancher, observability, or apps."
        exit 1
        ;;
    esac

    echo "==> Running postboot on all ${CLUSTER} nodes in parallel"
    for NODE in "${NODES[@]}"; do
      echo "    ${NODE}: starting postboot"
      ssh "sles@${NODE}" "sudo -i bash ~sles/Scripts/install_RKE2_postboot.sh" &
    done

    echo "==> Waiting for all nodes to complete..."
    wait

    KUBECONFIG_DEST="${HOME}/.kube/enclave-${CLUSTER}.kubeconfig"
    mkdir -p "${HOME}/.kube"
    echo "==> Fetching kubeconfig from ${GENESIS} → ${KUBECONFIG_DEST}"
    scp "sles@${GENESIS}:.kube/config" "${KUBECONFIG_DEST}"
    echo "==> Done. Test with: kubectl --kubeconfig ${KUBECONFIG_DEST} get nodes"
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# NODE MODE — must be root
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Must be run as root."
  exit 1
fi

if [[ ! -f /root/.rke2.vars ]]; then
  echo "ERROR: /root/.rke2.vars not found. Was install_RKE2.sh run first?"
  exit 1
fi

source /root/.rke2.vars

echo "==> Waiting for rke2.yaml to appear..."
for i in $(seq 1 30); do
  [[ -f /etc/rancher/rke2/rke2.yaml ]] && break
  echo "  attempt ${i}/30..."
  sleep 10
done

if [[ ! -f /etc/rancher/rke2/rke2.yaml ]]; then
  echo "ERROR: /etc/rancher/rke2/rke2.yaml not found after waiting. Is rke2-server running?"
  exit 1
fi

mkdir -p /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
chmod 600 /root/.kube/config
sed -i "s/127.0.0.1/${MY_RKE2_VIP}/g" /root/.kube/config

mkdir -p ~sles/.kube 2>/dev/null || true
cp /root/.kube/config ~sles/.kube/config 2>/dev/null || true
chown -R sles ~sles/.kube/ 2>/dev/null || true

export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin
export KUBECONFIG=/root/.kube/config
echo "==> kubeconfig configured. Nodes:"
kubectl get nodes
