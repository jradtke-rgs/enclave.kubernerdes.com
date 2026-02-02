# README

This single repository contains the overview, architecture, and implementation steps to deploy RGS stack on small form factor PC (Intel NUC).

This is NOT an official repository.  It is meant to be a quick way to build a lab environment using the "easy methods" to get things working.

## Status
Status: Work in Progress (Jan 2026)

This is mostly a collection of scripts, notes, etc.. at this point.  It will change significantly to be more of a guide and reference.

## Environment Overview
The "admin host" (nuc-00) will have access to the Internet to pull down necessary bits, including this REPO. (either community or RGS)
Once the software has been acquired, the Internet link can be disconnected and the environment can be built absent of external connectivity.

[Hardware Inventory and Description](./Hardware.md)

![Kubernerdes Enclave Hardware](Images/KubernerdesEnclaveHardware.png)

## High-level steps
- Build nuc-00 (physical node)
- Build nuc-00-01/nuc-00-02 (virtual machines)
- Build Harvester Cluster
- Install Rancher Manager Server (RMS) on Harvester Cluster
- Deploy Kubernetes using RMS (Leap Micro + K3s)
- Deploy Kubernetes using RMS (Leap + RKE2)

## TODO
While this repo is available via HTTP/S, I will make all the content available or sourced from a USB device, and then shared from the nuc-00, to emulate an airgap deploy.

## Links

### References
[Harvester Community Images](https://github.com/harvester/harvester/releases)

[Carbide Portal](https://portal.ranchercarbide.dev/product/)
[Hauler - Product Page](https://ranchergovernment.com/products/hauler)  
[Hauler - Docs](https://docs.hauler.dev/docs/intro)

### Videos, Blogs, Walkthroughs, etc..
[Harvester + Kasm - GPU Passthrough](https://www.youtube.com/watch?v=3tMfc0fUvk4)  
[Kasm Technologies and Rancher Government Solutions Partner to Deliver Enterprise-Class Kubernetes-Powered VDI](https://www3-develop.kasmweb.com/alliance-partnership/rancher-government-solutions)  

[Three Easy-Mode Ways of Installing Rancher onto Harvester](https://ranchergovernment.com/blog/three-easy-mode-ways-of-installing-rancher-onto-harvester)
