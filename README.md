# README

This single repository contains the overview, architecture, and implementation steps to deploy the components of the RGS stack using Carbide on small form factor PC (Intel NUC).  A similar REPO will be created later demonstrating the same, but using RGS bits and endpoints.

This is NOT an official repository.  It is meant to be a quick way to build a lab environment using the "easy methods" to get things working.

Advice: things are changing frequently in the cloud-native space.  I have developed a habit to ensure I check for the most current sources.  (i.e. a video published in June of last year, was probably started around April/May - and is most likely a bit dated).

## Status
Status: Work in Progress (Feb 2026)

This is mostly a collection of scripts, notes, etc.. at this point.  It will change significantly to be more of a guide and reference.

## Goals

A self-sustaining network enclave with:
* Infrastructure node hosting DNS, PXE build
* 3-node Harvester cluster 
* Rancher Manager Server
* Kubernetes cluster hosting Applications
* [bonus] Integrated NVIDIA AI hardware with RGS K8s/cloud-native stack

## Prerequisites

* request (and receive) Carbide License
* 3 x NUCs that are configured identically (re: Storage/Network Interfaces)
* 1 x system with Keyboard/Video/Mouse for administrating resources (I use another NUC)
* Internet connectivity
* [Hardware - Overview](./Hardware.md)

## Environment Overview
The "admin host" (nuc-00) will have access to the Internet to pull down necessary bits, including this REPO. 
Once the software has been acquired, the Internet link can be disconnected and the environment can be built, and managed, absent of external connectivity.

[Hardware Inventory and Description](./Hardware.md)

![Kubernerdes Enclave Hardware](Images/KubernerdesEnclaveHardware.png)

## High-level steps
- Build nuc-00 (physical node - "admin or infra host")
- Build nuc-00-01/nuc-00-02 (virtual machines - "DNS and PXE hosts")
- Build Harvester Cluster
- Deploy 3 x Linux VMs to host Rancher Manager Server (RMS)
- Install K3s/RKE2 on Linux VMs, then install Rancher Manager Server 
- Deploy Kubernetes using RMS (Leap Micro + K3s)
- Deploy Kubernetes using RMS (Leap + RKE2)

## TODO
While this repo is available via HTTP/S, I will make all the content available or sourced from a USB device, and then shared from the nuc-00, to emulate an airgap deploy.

## Links

### Guides
[Harvester Intro and Setup - includes VM deployment](https://www.suse.com/c/rancher_blog/harvester-intro-and-setup/)   
[Deploy Rancher Manager - Helm CLI Quick Start](https://ranchermanager.docs.rancher.com/getting-started/quick-start-guides/deploy-rancher-manager/helm-cli)  
[Virtualization on Kubernetes with Harvester](https://ranchermanager.docs.rancher.com/integrations-in-rancher/harvester)  


### References
[Harvester Community Images](https://github.com/harvester/harvester/releases)

[Carbide Portal](https://portal.ranchercarbide.dev/product/)
[Hauler - Product Page](https://ranchergovernment.com/products/hauler)  
[Hauler - Docs](https://docs.hauler.dev/docs/intro)

### Videos, Blogs, Walkthroughs, etc...

[Harvester + Kasm - GPU Passthrough](https://www.youtube.com/watch?v=3tMfc0fUvk4)  
[Kasm Technologies and Rancher Government Solutions Partner to Deliver Enterprise-Class Kubernetes-Powered VDI](https://www3-develop.kasmweb.com/alliance-partnership/rancher-government-solutions)  

[Three Easy-Mode Ways of Installing Rancher onto Harvester](https://ranchergovernment.com/blog/three-easy-mode-ways-of-installing-rancher-onto-harvester)
