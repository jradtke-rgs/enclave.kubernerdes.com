#---
# While this *IS* shell commands, I am not making this excutable or runable
# I just put this together to do the job it does as I am rebuilding my environment 
#   fairly often while testing currently

CLUSTERNAME=enclave-harvester
cp ~/Downloads/local.yaml ~/.kube/$CLUSTERNAME.kubeconfig
export KUBECONFIG=~/.kube/$CLUSTERNAME.kubeconfig
sed -i -e 's/harvester.enclave.kubernerdes.com/10.10.12.100/g' $KUBECONFIG
kubectl get nodes

rename_kube_cluster() {
  export local OLD="${1:-local}"
  export local NEW="$2"

  yq e '(.clusters[] | select(.name == env(OLD)) | .name) = env(NEW)' -i $KUBECONFIG
  yq e '(.contexts[] | select(.context.cluster == env(OLD)) | .context.cluster) = env(NEW)' -i $KUBECONFIG
  yq e '(.contexts[] | select(.name == env(OLD)) | .name) = env(NEW)' -i $KUBECONFIG

  echo "Renamed cluster context '$OLD' → '$NEW'"
  kubectl config get-contexts
  unset OLD
  unset NEW
}

# Usage
# rename_kube_cluster local enclave-harvester

DESTINATIONS="mansible@10.10.12.10:.kube/
10.10.12.10:/srv/www/.kube/
root@10.10.12.10:.kube/"

echo "Cut-and-paste the following output"

for DEST in $DESTINATIONS
do 
  echo "scp $KUBECONFIG $DEST"
done

