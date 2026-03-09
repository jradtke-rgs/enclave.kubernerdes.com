# Troubleshooting Reference

A collection of useful commands and procedures for diagnosing common issues in the enclave environment.

---

## Force Delete an Orphaned Cluster

If the Rancher UI shows a cluster count that doesn’t match what’s listed in the pane, you may have an orphaned or phantom cluster. Ensure you’re using the correct kubeconfig/context before proceeding.

Review what clusters Rancher knows about:
```bash
kubectl get clusters.management.cattle.io
```

Check for clusters stuck in “provisioning” status:
```bash
kubectl -n fleet-default get clusters.provisioning.cattle.io
```

Delete the orphaned cluster:
```bash
kubectl -n fleet-default delete cluster.provisioning.cattle.io <cluster-name>
```

---

## Stuck Cluster Deletion (Finalizer Removal)

If a cluster delete is permanently stuck, you can clear the finalizers to force removal:

```bash
kubectl get clusters.management.cattle.io   # identify the cluster ID
export CLUSTERID=”c-xxxxxxxxx”
kubectl patch clusters.management.cattle.io $CLUSTERID -p ‘{“metadata”:{“finalizers”:}}’ --type=merge
kubectl delete clusters.management.cattle.io $CLUSTERID
```

---

## Networking

### Inspect Pod and Service CIDRs

```bash
echo “podCIDR: $(kubectl get nodes -o jsonpath=’{.items[*].spec.podCIDR}’)”
echo “Cluster-IP Range: $(kubectl cluster-info dump | grep -m 1 service-cluster-ip-range)”
```

### PXE Boot Traffic Capture

```bash
tcpdump -i <interface> -n -vv \
  ‘(port 67 or port 68 or port 69 or port 80) and (host 10.10.12.101 or host 10.10.12.102 or host 10.10.12.111)’ \
  -w /tmp/pxe-boot.pcap
tail -f /var/log/apache2/access_log
```

---

## Certificate Inspection

### View the full certificate chain

```bash
HOST=observability.kubernerdes.lab
PORT=6443
openssl s_client \
  -servername “$HOST” \
  -showcerts \
  -connect “$HOST:$PORT” \
  < /dev/null 2>/dev/null
```

### Extract SHA-1 fingerprints from a certificate chain

```bash
HOST=observability.kubernerdes.lab
PORT=’443’; \
openssl s_client \
  -servername “$HOST” \
  -showcerts \
  -connect “$HOST:$PORT” \
  < /dev/null 2>/dev/null \
  | awk ‘/BEGIN/,/END/{ if(/BEGIN/){a++}; print}’ \
  | {
    cert_text=””
    while IFS= read -r line; do
      case “$line” in
        *”END CERTIFICATE”*)
          cert_text=”$cert_text$line
“
          printf ‘%s’ “$cert_text” \
            | openssl x509 \
              -fingerprint \
              -sha1 \
              -noout
          cert_text=””
          ;;
        *)
          cert_text=”$cert_text$line
“
          ;;
      esac
    done
  } \
  | awk -F’=’ ‘{print $2}’ \
  | sed ‘s/://g’ \
  | tr ‘[:upper:]’ ‘[:lower:]’
```

### Compare certificate behavior — IP vs. hostname (SNI)

```bash
echo | openssl s_client -connect 10.10.12.100:443 > /tmp/ssl_output.0
echo | openssl s_client -connect 10.10.12.100:443 -servername harvester-edge.enclave.kubernerdes.com > /tmp/ssl_output.1
sdiff /tmp/ssl_output.0 /tmp/ssl_output.1
echo | openssl s_client -connect 10.10.12.100:443 -showcerts > /tmp/ssl_output.0
```

---

## Rancher Manager Diagnostics

### Pod and deployment status

```bash
kubectl -n cattle-system get pods -l app=rancher -o wide
kubectl -n cattle-system logs -l app=cattle-agent
kubectl -n cattle-system logs -l app=cattle-cluster-agent
kubectl -n cattle-system get deployment
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system rollout status deploy/rancher-webhook
```

### RKE2 service logs

```bash
systemctl status rke2-server.service
journalctl -xeu rke2-server.service
```

### Compare certificates across cluster nodes

```bash
openssl s_client -connect 127.0.0.1:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.0
openssl s_client -connect 10.10.12.121:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.1
openssl s_client -connect 10.10.12.120:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.2
```

### Discover Service ClusterIP CIDR and Pod CIDR

```bash
# Service ClusterIP CIDR (trick: apply an invalid ClusterIP and read the error)
echo ‘{“apiVersion”:”v1”,”kind”:”Service”,”metadata”:{“name”:”tst”},”spec”:{“clusterIP”:”1.1.1.1”,”ports”:[{“port”:443}]}}’ | kubectl apply -f - 2>&1 | sed ‘s/.*valid IPs is //’

# Pod CIDR
kubectl get nodes -o jsonpath=’{.items[*].spec.podCIDR}’
```

### DNS debugging

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl run -i --tty --rm debug --image=busybox --restart=Never -- sh

kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
kubectl exec -i -t dnsutils -- nslookup kubernetes.default
```

---

## Hauler — Query Carbide Registry Tags

List available tags for Rancher-related images in the Carbide registry:

```bash
source ~/.hauler/credentials && for repo in rancher/rancher rancher/shell rancher/fleet rancher/webhook \
   rancher/rancher-agent rancher/system-agent carbide/nginx-html-base nginx-html-base rancher/mirrored-nginx \
   rancher/hardened-nginx; do TOKEN=$(curl -s -u “${HAULER_USER}:${HAULER_PASSWORD}” \
   “https://rgcrprod.azurecr.us/oauth2/token?service=rgcrprod.azurecr.us&scope=repository:${repo}:pull” | python3 -c \
    “import sys,json; print(json.load(sys.stdin).get(‘access_token’,’’))”) && RESULT=$(curl -s -w “\n%{http_code}” \
   -H “Authorization: Bearer $TOKEN” “https://rgcrprod.azurecr.us/v2/${repo}/tags/list”) && CODE=$(echo “$RESULT” | \
   tail -1) && BODY=$(echo “$RESULT” | head -1) && if [ “$CODE” = “200” ]; then echo “FOUND: $repo”; echo “  Tags: \
   $(echo $BODY | python3 -c “import sys,json; tags=json.load(sys.stdin).get(‘tags’,[]); print(‘, \
   ‘.join(tags[:10]))”) ...”; fi; done
```
