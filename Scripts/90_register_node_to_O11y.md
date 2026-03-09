# Register a Cluster with SUSE Observability

This is an intentionally manual process (not a script) — the steps require retrieving values from the web UI and confirming cluster connectivity before proceeding.

## Setup

1. Set `CLUSTER_NAME` to the name you used when creating the StackPack in the Observability UI
2. Retrieve the `SERVICE_TOKEN` from the SUSE Observability web UI

## Install the Agent

```bash
CLUSTER_NAME=harvester   # Set to the cluster you are registering
# CLUSTER_NAME=rancher   # (or whichever cluster)

export KUBECONFIG=~/.kube/enclave-${CLUSTER_NAME}.kubeconfig
kubectl get nodes   # Confirm kubectl is working and pointing at the correct cluster

helm repo add suse-observability https://charts.rancher.com/server-charts/prime/suse-observability
helm repo update
helm upgrade --install \
  --namespace suse-observability \
  --create-namespace \
  --set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
  --set-string 'stackstate.cluster.name'=$CLUSTER_NAME \
  --set-string 'stackstate.url'='https://observability.enclave.kubernerdes.com/receiver/stsAgent' \
  --set 'nodeAgent.skipKubeletTLSVerify'=true \
  --set-string 'global.skipSslValidation'=true \
  suse-observability-agent suse-observability/suse-observability-agent
```

## Reference — Default Install (without TLS customization)

For comparison, this is the default Helm command without the TLS skip flags:

```bash
helm upgrade --install \
  --namespace suse-observability \
  --create-namespace \
  --set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
  --set-string 'stackstate.cluster.name'='rancher' \
  --set-string 'stackstate.url'='https://observability.enclave.kubernerdes.com/receiver/stsAgent' \
  suse-observability-agent suse-observability/suse-observability-agent
```

