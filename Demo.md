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
  - create Cluster Network Configuration (similar to vSphere Distributed Switch vDS) - must be same on all nodes
  - create Network Configuration (select the nodes and assign the uplink)
  - create a Virtual Machine Network (assign the Cluster Network to use, and select Type
    - L2VLanNetwork (and assign VlanID)
    - UntaggedNetwork (bridged to physical)
    - OverlayNetwork (Host-only networking)
- Create Namespace for VMs (this is a personal preference)
- Upload Cloud Image (QCOW2)
- Deploy a VM in to Namespace

# Extra-curricular (if time permits)

- Walkthrough of Rancher Manager integration

# Airgap Install

- Carbide Portal - access software from RGS
- hauler - tool for pulling down software assets for distribution in airgap

# Links
[harvester UI](http://harvester.homelab.kubernerdes.com)  
[Rancher UI](http://rancher.homelab.kubernerdes.com)  
   
[Harvester Community Images](https://github.com/harvester/harvester/releases)    

[Hauler - Product Page](https://ranchergovernment.com/products/hauler)  
[Hauler - Docs](https://docs.hauler.dev/docs/intro)
[Carbide Portal](https://portal.ranchercarbide.dev/product/)

## Videos, Walkthroughs, etc..
[Harvester + Kasm - GPU Passthrough](https://www.youtube.com/watch?v=3tMfc0fUvk4)  
[Kasm Technologies and Rancher Government Solutions Partner to Deliver Enterprise-Class Kubernetes-Powered VDI](https://www3-develop.kasmweb.com/alliance-partnership/rancher-government-solutions)

