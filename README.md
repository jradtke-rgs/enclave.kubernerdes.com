# README

This single repository contains the overview, architecture, and implementation steps to deploy RGS stack on small form factor PC (Intel NUC).

This is NOT an official repository.  It is meant to be a quick way to build a lab environment using the "easy methods" to get things working.

## Status
This is mostly a collection of scripts, notes, etc.. at this point.  It will change significantly to be more of a guide and reference.

[Hardware Inventory and Description](./Hardware.md)

# TODO
While this repo is available via HTTP/S, I will make all the content available or sourced from a USB device, and then shared from the nuc-00, to emulate an airgap deploy.


- Build nuc-00 (physical node)
- Build nuc-00-01/nuc-00-02 (virtual machines)
- Build Harvester Cluster
- Install Rancher Manager Server (RMS) on Harvester Cluster
- Deploy Kubernetes using RMS (Leap Micro + K3s)
- Deploy Kubernetes using RMS (Leap + RKE2)

![Kubernerdes Enclave Hardware](Images/KubernerdesEnclaveHardware.png)

