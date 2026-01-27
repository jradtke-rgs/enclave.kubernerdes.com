# Demo Walkthrough


# Prerequisites

| Item | Purpose/Reason |
|:-----|:---------------| 
| VIP | The IP used for Harvester UI |
| IPs | Each node needs an IP address - I prefer to use static |
| DHCP | (optional) |
| DNS | You should have a working DNS environment - we need the IPs of the DNS Servers |
| Harvester Image | You can find the community bits at Github (link below), or pull from Carbide |
| Cloud Images | Download from vendor, or create your own (typically for Windows VMs) |
| Password | to login to hosts, either at the console, or ssh |
| Cluster Token | common phrase for nodes to join Harvester Cluster |


# Deployment 

## Harvester

- Deploy node using USB boot
  - (we will briefly cover PXE boot)

# Post-Deploy

- Login to Harvester UI (set password)
- Download Kubeconfig for Harvester
- Create Networking for Virtual Machines
- Create Namespace
- Upload Cloud Image (QCOW2)
- Deploy a VM


# Extra-curricular (if time permits)

- Walkthrough of Rancher Manager integration

# Links
[KVM for host](http://10.10.12.111/)  
[harvester UI](http://harvester.homelab.kubernerdes.com)  
[Rancher UI](http://rancher.homelab.kubernerdes.com)  
   
[Harvester Community Images](https://github.com/harvester/harvester/releases)    
[Carbide Portal](https://portal.ranchercarbide.dev/product/)

