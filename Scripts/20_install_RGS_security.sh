# This "script" was not intended to be run as a script, and instead cut-and-paste the pieces (hence no #!/bin/sh at the top ;-)
# Reference: https://open-docs.neuvector.com/deploying/kubernetes
# Reference: https://ranchermanager.docs.rancher.com/integrations-in-rancher/neuvector

# Deply RGS Security (NeuVector) on the "applications" cluster

export KUBECONFIG=~/.kube/enclave-applications.kubeconfig

#######################################
# Install SUSE Security (NeuVector)
#######################################

# Add the NeuVector Helm repo
helm repo add neuvector https://neuvector.github.io/neuvector-helm/
helm repo update

# Create namespace
kubectl create namespace cattle-neuvector-system

# Install NeuVector via Helm
helm upgrade --install neuvector neuvector/core \
  --namespace cattle-neuvector-system \
  --set manager.svc.type=ClusterIP \
  --set controller.replicas=3 \
  --set cve.scanner.replicas=2 \
  --set controller.pvc.enabled=false \
  --set k3s.enabled=false \
  --set manager.ingress.enabled=false \
  --set global.cattle.url=https://rancher.enclave.kubernerdes.com

# Wait for pods to be ready
kubectl get pods -n cattle-neuvector-system -w

#######################################
# Create Ingress for NeuVector Manager
#######################################
cat << EOF > neuvector-ingress.yaml
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neuvector-manager
  namespace: cattle-neuvector-system
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
spec:
  ingressClassName: nginx
  rules:
    - host: neuvector.applications.enclave.kubernerdes.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: neuvector-service-webui
                port:
                  number: 8443
  tls:
    - hosts:
        - neuvector.applications.enclave.kubernerdes.com
EOF

kubectl apply -f neuvector-ingress.yaml

# Verify ingress
kubectl get ingress -n cattle-neuvector-system

# Retrieve bootstrap password
echo "NeuVector UI: https://neuvector.applications.enclave.kubernerdes.com"
echo "Bootstrap password: $(kubectl get secret --namespace cattle-neuvector-system neuvector-bootstrap-secret -o go-template='{{ .data.bootstrapPassword|base64decode}}{{ "\n" }}')"

exit 0
