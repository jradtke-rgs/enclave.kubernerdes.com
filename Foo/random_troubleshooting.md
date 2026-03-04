# Random Troubleshooting

## Force Delete a cluster
If you happen to login to your Rancher UI and click on Cluster and see there is a count of 2, but you only see 1 listed in the pane, you may want/need to delete the orphaned/phantom cluster

Make sure you are using the correct Kubeconfig/context

Review what clusters Rancher knows about
```bash
kubectl get clusters.management.cattle.io 
```

See if there are cluster still in "provisioning" status
```bash
kubectl -n fleet-default get clusters.provisioning.cattle.io
```

```bash
kubectl -n fleet-default delete cluster.provisioning.cattle.io <cluster-name>
```

## Networking 
```
echo "podCIDR: $(kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}') "
echo "Cluster-IP Range: $(kubectl cluster-info dump | grep -m 1 service-cluster-ip-range)"

### Networking: PXE
```
tcpdump -i <interface> -n -vv \ '(port 67 or port 68 or port 69 or port 80) and (host 10.10.12.101 or host 10.10.12.102 or host 10.10.12.111)' \ -w /tmp/pxe-boot.pcap
tail -f /var/log/apache2/access_log
```

## Cert review

```
HOST=observability.kubernerdes.lab
PORT=6443
openssl s_client \
  -servername "$HOST" \
  -showcerts \
  -connect "$HOST:$PORT" \
  < /dev/null 2>/dev/null
```

```
HOST=observability.kubernerdes.lab
PORT='443'; \
openssl s_client \
  -servername "$HOST" \
  -showcerts \
  -connect "$HOST:$PORT" \
  < /dev/null 2>/dev/null \
  | awk '/BEGIN/,/END/{ if(/BEGIN/){a++}; print}' \
  | {
    cert_text=""
    while IFS= read -r line; do
      case "$line" in
        *"END CERTIFICATE"*)
          cert_text="$cert_text$line
"
          printf '%s' "$cert_text" \
            | openssl x509 \
              -fingerprint \
              -sha1 \
              -noout
          cert_text=""
          ;;
        *)
          cert_text="$cert_text$line
"
          ;;
      esac
    done
  } \
  | awk -F'=' '{print $2}' \
  | sed 's/://g' \
  | tr '[:upper:]' '[:lower:]'
```

### 
Differentiate between using IP and the hostname
```
echo | openssl s_client -connect 10.10.12.100:443 > /tmp/ssl_output.0
echo | openssl s_client -connect 10.10.12.100:443 -servername harvester-edge.enclave.kubernerdes.com > /tmp/ssl_output.1
sdiff /tmp/ssl_output.0 /tmp/ssl_output.1
echo | openssl s_client -connect 10.10.12.100:443 -showcerts > /tmp/ssl_output.0
```
## Cluster Delete

If you manage to find yourself with a "stuck cluster delete"....
```
kubectl get clusters.management.cattle.io # find the cluster you want to delete
export CLUSTERID=“c-xxxxxxxxx” #
kubectl patch clusters.management.cattle.io $CLUSTERID -p ‘{“metadata”:{“finalizers”:}}’ --type=merge
kubectl delete clusters.management.cattle.io $CLUSTERID
```

## Rancher Manager
```
kubectl -n cattle-system get pods -l app=rancher -o wide
kubectl -n cattle-system logs -l app=cattle-agent
kubectl -n cattle-system logs -l app=cattle-cluster-agentA
kubectl -n cattle-system get deployment
kubectl -n cattle-system rollout status deploy/rancher
kubectl -n cattle-system rollout status deploy/rancher-webhook

See "systemctl status rke2-server.service" and "journalctl -xeu rke2-server.service" for details.
openssl s_client -connect 127.0.0.1:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.0
openssl s_client -connect 10.10.12.121:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.1
openssl s_client -connect 10.10.12.120:6443 -showcerts </dev/null | openssl x509 -noout -text > cert.2

# service ClusterIP CIDR
echo '{"apiVersion":"v1","kind":"Service","metadata":{"name":"tst"},"spec":{"clusterIP":"1.1.1.1","ports":[{"port":443}]}}' | kubectl apply -f - 2>&1 | sed 's/.*valid IPs is //'
# Pod CIDR
kubectl get nodes -o jsonpath='{.items[*].spec.podCIDR}'

##
kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
kubectl run -i --tty --rm debug --image=busybox --restart=Never -- sh

kubectl apply -f https://k8s.io/examples/admin/dns/dnsutils.yaml
kubectl exec -i -t dnsutils -- nslookup kubernetes.default
```
