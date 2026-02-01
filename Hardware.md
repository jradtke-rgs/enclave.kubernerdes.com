# Hardware

## Systems

| System     | Purpose           | Model       | CPU | CPU model | Mem | Disk0 (SSD) | Disk1 NVMe |
|:-----------|:------------------|:------------|:----|:----------|:----|:------|:------|
| nuc-00     | Admin Host        | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-01     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-02     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-03     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |

## Peripherals

| Qty | Object |
|:---:|:-------|
| 3 | sipeed nanaKVM + HDMI cable + USB-C Cable |
| 4 | Chicony A17-120P2A 20V 6A 120W Power Supply |
| 3 | 1GB USB-C Network Adapter |
| 1 | 8-port 1gb Network Switch |
| 1 | portable monitor |
| 1 | power strip |
| 1 | mouse |
| 1 | keyboard |


| Port | Host     | Purpose | Port | Host     | Purpose |
|:--:|:-----------|:------|:--:|:-------|:----|
| 1  | nuc-00     | | 9 | nuc-02-kvm | |
| 2  | nuc-01     | | 10 | nuc-02-kvm | | 
| 3  | nuc-02     | | 11 | |
| 4  | nuc-03     | | 12 | |
| 5  | nuc-01-vms | | 13 | |
| 6  | nuc-02-vms | | 14 | |
| 7  | nuc-03-vms | | 15 | |
| 8  | nuc-01-kvm | | 16 | uplink | | 
