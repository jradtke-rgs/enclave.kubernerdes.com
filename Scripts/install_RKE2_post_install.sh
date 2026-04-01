#!/bin/bash
set -euo pipefail

# install_RKE2_post_install.sh — Kubeconfig setup after RKE2 node reboot
#
# Run as root on each node after it comes back up from the post-install reboot.
# On SL-Micro this is handled automatically by the rke2-postboot.service one-shot
# installed by install_RKE2.sh. Use this script as a manual fallback if needed.

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

if [[ ! -f /root/.rke2.vars ]]; then
  echo "ERROR: /root/.rke2.vars not found. Was install_RKE2.sh run on this node?"
  exit 1
fi

source /root/.rke2.vars
export PATH=$PATH:/opt/rke2/bin:/var/lib/rancher/rke2/bin

mkdir -p /root/.kube
cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
chown root /root/.kube/config
sed -i -e "s/127.0.0.1/${MY_RKE2_VIP}/g" /root/.kube/config

mkdir -p ~sles/.kube 2>/dev/null || true
cp /root/.kube/config ~sles/.kube/config 2>/dev/null || true
chown -R sles ~sles/.kube/ 2>/dev/null || true

export KUBECONFIG=/root/.kube/config
kubectl get nodes
