# Demo Walkthrough

A guided walkthrough for deploying Harvester and standing up the initial environment. This covers the core installation, post-deployment configuration, and optional Rancher Manager integration.

## Prerequisites

| Item | Purpose |
|:-----|:--------|
| VIP | Virtual IP address for the Harvester UI |
| IPs | One static IP per node (recommended over DHCP) |
| DHCP | Optional — only needed if not using static IPs |
| DNS | Working DNS environment; you'll need the DNS server IPs |
| Harvester Image | Community ISO from [GitHub Releases](https://github.com/harvester/harvester/releases), or pulled via Carbide |
| Cloud Images | Vendor-provided QCOW2 images, or custom-built (typically for Windows VMs) |
| Password | Credentials for console and SSH access to hosts |
| Cluster Token | Shared passphrase used by nodes to join the Harvester cluster |

## Deployment

### Harvester Installation

- Deploy nodes using USB boot
  - PXE boot is also supported — see the [PXE Overview](./Docs/PXE-Overview.md)

## Post-Deployment Configuration

1. Log in to the Harvester UI and set the admin password
2. Download the Kubeconfig for the Harvester cluster
3. **Configure networking for Virtual Machines:**
   - Create a **Cluster Network** (similar to a vSphere Distributed Switch) — must be consistent across all nodes
   - Create a **Network Configuration** — select nodes and assign the uplink interface
   - Create a **VM Network** — assign the Cluster Network and choose a type:
     - `L2VlanNetwork` — tagged VLAN traffic (specify VLAN ID)
     - `UntaggedNetwork` — bridged directly to the physical network
     - `OverlayNetwork` — host-only / isolated networking
4. Create a namespace for VMs (optional, but recommended for organization)
5. Upload a cloud image (QCOW2 format)
6. Deploy a VM into the namespace

## Extra Credit (if time permits)

- Walkthrough of Rancher Manager integration with Harvester

## Airgap Installation

- **Carbide Portal** — access and download software from RGS
- **Hauler** — CLI tool for pulling and packaging software assets for air-gapped distribution

---

## Demo Links

| Resource | URL |
|:---------|:----|
| Harvester UI | http://harvester.homelab.kubernerdes.com |
| Rancher UI | http://rancher.homelab.kubernerdes.com |

For additional references, see the [README](./README.md).
