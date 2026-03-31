#!/bin/bash

# Note:  this is in a separate script that should run after the have been rebooted.
# SL Micro Nodes seem to require it this way, and SLES nodes will work using this method

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
