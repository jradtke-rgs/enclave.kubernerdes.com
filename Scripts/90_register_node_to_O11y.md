# Manual registration for Observability Clients

This is NOT a script, and for a good reason.  This is a bit of a convoluted process that I need to get sorted later.

Set the variable for CLUSTERNAME # This is whatever you provided when you created the stackpack in the WebUI
Retrieve the SERVICE_TOKEN from the StackState WebUI

# Let's roll
```
CLUSTER_NAME=harverster # Select a host that you are adding
CLUSTER_NAME=rancher 

export KUBECONFIG=~/.kube/enclave-${CLUSTER_NAME}.kubeconfig
kubectl get nodes # Confirm kubectl works and pointing at correct cluster

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



This is an example of the default provided (which does not have the tls customizatio)
```
helm upgrade --install \
--namespace suse-observability \
--create-namespace \
--set-string 'stackstate.apiKey'=$SERVICE_TOKEN \
--set-string 'stackstate.cluster.name'='rancher' \
--set-string 'stackstate.url'='https://observability.enclave.kubernerdes.com/receiver/stsAgent' \
suse-observability-agent suse-observability/suse-observability-agent
```

