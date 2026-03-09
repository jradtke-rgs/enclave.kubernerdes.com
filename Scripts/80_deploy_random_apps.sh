
## ADD GIT CLONE, CD, etc...

##t Then...
# Create namespace
KUBECONFIG=~/.kube/enclave-applications.kubeconfig kubectl create namespace hexgl
# Deploy
KUBECONFIG=~/.kube/enclave-applications.kubeconfig kubectl apply -k k8s/overlays/example

cat << EOF > ingress-hexgl.yaml
--
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: hexgl
  namespace: hexgl
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
spec:
  ingressClassName: nginx
  rules:
    - host: hexgl.applications.enclave.kubernerdes.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: hexgl
                port:
                  number: 80
EOF 

kubectl apply -f ingress-hexgl.yaml
