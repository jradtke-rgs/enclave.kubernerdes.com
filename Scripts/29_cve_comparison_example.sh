# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-)
# Reference: https://open-docs.neuvector.com/deploying/kubernetes
# Reference: https://ranchermanager.docs.rancher.com/integrations-in-rancher/neuvector
# Reference: https://rancherfederal.github.io/carbide-docs/docs/registry-docs/downloading-images

# SUSE Security (NeuVector) on the "applications" cluster
# SSH:   ssh -i ~/.ssh/id_rsa-kubernerdes sles@<IP>

# Configure correct K8s cluster
export KUBECONFIG=~/.kube/enclave-applications.kubeconfig

#######################################
# CVE Comparison: Community vs Carbide
#######################################
# Deploy Rancher pods to compare community vs Carbide (hardened) images in NeuVector.
# The Carbide registry (rgcrprod.azurecr.us) provides hardened Rancher ecosystem
# images with fewer CVEs. See carbide-images.txt for the full list:
#   https://github.com/rancherfederal/carbide-releases/blob/main/carbide-images.txt

RANCHER_VERSION="v2.13.3"

# #########################################
## COMMUNITY CONTAINER
# #########################################
NAMESPACE=cvet-rancher-comm
kubectl create namespace ${NAMESPACE}

# Community Rancher image (from Docker Hub)
cat << EOF | kubectl apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: rancher-community
  namespace: ${NAMESPACE}
  labels:
    app: rancher
    source: community
spec:
  containers:
  - name: rancher
    image: docker.io/rancher/rancher:${RANCHER_VERSION}
    command: ["sleep", "infinity"]
EOF

kubectl wait --for=condition=Ready pod/rancher-community -n ${NAMESPACE} --timeout=120s
kubectl get pods -n ${NAMESPACE}

# #########################################
## CARBIDE CONTAINER
# #########################################
NAMESPACE=cvet-rancher-carb
kubectl create namespace ${NAMESPACE}

#   Carbide credentials must exist in ~/.hauler/credentials with:
#     HAULER_USER, HAULER_PASSWORD, HAULER_SOURCE_REPO_URL
#
source ~/.hauler/credentials
hauler login "$HAULER_SOURCE_REPO_URL" -u "$HAULER_USER" -p "$HAULER_PASSWORD"

# Create imagePullSecret so kubelet can pull from the Carbide registry
kubectl create secret docker-registry carbide-registry \
  --namespace ${NAMESPACE} \
  --docker-server="$HAULER_SOURCE_REPO_URL" \
  --docker-username="$HAULER_USER" \
  --docker-password="$HAULER_PASSWORD"

# Carbide Rancher image (hardened, from rgcrprod.azurecr.us)
cat << EOF | kubectl apply -f -
---
apiVersion: v1
kind: Pod
metadata:
  name: rancher-carbide
  namespace: ${NAMESPACE}
  labels:
    app: rancher
    source: carbide
spec:
  imagePullSecrets:
  - name: carbide-registry
  containers:
  - name: rancher
    image: rgcrprod.azurecr.us/rancher/rancher:${RANCHER_VERSION}
    command: ["sleep", "infinity"]
EOF

kubectl wait --for=condition=Ready pod/rancher-carbide -n ${NAMESPACE} --timeout=120s
kubectl get pods -n ${NAMESPACE}

# #########################################
## CLEANUP (when done with the comparison)
# #########################################
# kubectl delete namespace cvet-rancher-comm cvet-rancher-carb

exit 0
