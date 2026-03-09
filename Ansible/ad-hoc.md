# Ansible Ad-Hoc Commands

A collection of commonly used ad-hoc Ansible commands for managing the enclave hosts.

## Basic Shell Commands

```bash
ansible -i hosts all -a "uptime"
ansible -i hosts all -m shell -a "uptime"
```

## Update and Restart Hosts

Update all packages across every host, then gracefully cycle the infrastructure — shut down VMs first, then restart the virtualization hosts (assuming VMs are configured to auto-start).

```bash
ansible -i hosts all -m yum -a "name=* state=latest" -b
ansible -i hosts InfraNodesAll -a "shutdown now -h"
ansible -i hosts InfraNodesVirtualMachines -a "shutdown now -r"
ansible -i hosts all -a "uptime"
```

## Hardware Info

```bash
ansible -i hosts -a "lscpu"
```
