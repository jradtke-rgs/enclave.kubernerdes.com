# Hardware

## Systems

| System     | Purpose           | Model       | CPU | CPU model | Mem | Disk0 (SSD) | Disk1 NVMe |
|:-----------|:------------------|:------------|:----|:----------|:----|:------|:------|
| nuc-00     | Admin Host        | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-01     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-02     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-03     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |

## Bill of Materials (BOM)

This is "what goes in the case" 

| Qty | Object | 
|:---:|:-------|
| 4 | [Intel NUC NUC13ANHi7](https://download.intel.com/newsroom/2023/client-computing/Intel-NUC-13-Pro-Product-Brief.pdf) |
| 4 | Chicony A17-120P2A 20V 6A 120W Power Supply (5.5mm - 2.5mm) |
| 3 | [sipeed nanoKVM + HDMI cable + USB-C Cable](https://wiki.sipeed.com/hardware/en/kvm/NanoKVM/introduction.html)
| 3 | 1GB USB-C Network Adapter |
| 1 | [NICGIGA 16-port 1gb Network Switch](https://www.nicgiga.com/products/16-port-2-5g-%E2%9E%95-2-port-10g-sfp-ethernet-switch-nicgiga-18-port-2-5gb-network-switch-unmanaged-plug-play-desktop-or-19-inch-rack-mount-fanless-metal-design) |
| 1 | [portable monitor Viewsonic VA1655](https://www.viewsonic.com/ph/products/lcd/VA1655) |
| 1 | power strip |
| 1 | mouse |
| 1 | keyboard |
| 1 | [Beryl AX (GL-MT3000) Travel Router](https://store-us.gl-inet.com/collections/travel-routers/products/beryl-ax-gl-mt3000-pocket-sized-wi-fi-6-wireless-travel-gigabit-router) |


## Switch Layout

Identifying network port connections (to determine what capacity I need)

| Port | Host     | Purpose | Port | Host       | Purpose |
|:--:|:-----------|:--------|:----:|:-----------|:----|
| 1  | nuc-00     |         | 9    | nuc-02-kvm | |
| 2  | nuc-01     |         | 10   | nuc-02-kvm | | 
| 3  | nuc-02     |         | 11   |            | |
| 4  | nuc-03     |         | 12   |            | |
| 5  | nuc-01-vms |         | 13   |            | |
| 6  | nuc-02-vms |         | 14   |            | |
| 7  | nuc-03-vms |         | 15   |            | |
| 8  | nuc-01-kvm |         | 16   | uplink     | | 
