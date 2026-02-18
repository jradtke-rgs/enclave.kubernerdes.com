# Hardware

## Systems

| System     | Purpose           | Model       | CPU | CPU model | Mem | Disk0 (SSD) | Disk1 NVMe |
|:-----------|:------------------|:------------|:----|:----------|:----|:------|:------|
| nuc-00     | Admin Host        | NUC13ANHi3  | 8   | i3-1315U  | 64  | 1024  | 1024  |
| nuc-01     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-02     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |
| nuc-03     | Harvester         | NUC13ANHi7  | 16  | i7-1360P  | 64  | 1024  | 1024  |

## Bill of Materials (BOM)

An inventory of "what goes in the case" 

| Total | Unit Cost | Qty | Object |
|------:|----------:|:---:|:-------|
| $350  | $350 | 1   | [Intel NUC NUC13ANHi3](https://download.intel.com/newsroom/2023/client-computing/Intel-NUC-13-Pro-Product-Brief.pdf) |
| $2,700 | $900 | 3   | [Intel NUC NUC13ANHi7](https://download.intel.com/newsroom/2023/client-computing/Intel-NUC-13-Pro-Product-Brief.pdf) |
| $304  | $76  | 4   | Chicony A17-120P2A 20V 6A 120W Power Supply (5.5mm - 2.5mm) |
| $150  | $50  | 3   | [sipeed nanoKVM + HDMI cable + USB-C Cable](https://wiki.sipeed.com/hardware/en/kvm/NanoKVM/introduction.html) |
| $36   | $12  | 3   | 1GB USB-C Network Adapter |
| $10   | $10  | 1   | [Multi Charging Cable,USB C Splitter Cable,3 in 1 Fast Charging Cord](https://www.amazon.com/dp/B0DT3Q9RCM?ref=ppx_yo2ov_dt_b_fed_asin_title&th=1) |
| $15   | $15  | 1   | [USB-A dual-port 45w charger]() |
| $110  | $110 | 1   | [portable monitor Viewsonic VA1655](https://www.viewsonic.com/ph/products/lcd/VA1655) |
| $20   | $10  | 2   | power strip |
| $7    | $7   | 1   | mouse |
| $60   | $60  | 1   | [Satechi Slim W1 Wired](https://www.bhphotovideo.com/c/product/1629629-REG/satechi_st_ucsw1m_slim_w1_wired_backlit.html) |
| $20   | $10  | 20  | 28 AWG Cat6 Network Cables (10 pack) |
| $99   | $99  | 1   | [Beryl AX (GL-MT3000) Travel Router](https://store-us.gl-inet.com/collections/travel-routers/products/beryl-ax-gl-mt3000-pocket-sized-wi-fi-6-wireless-travel-gigabit-router) |
| $279  | $279 | 1   | [Ubiquiti - USW-PRO-MAX-16](https://store.ui.com/us/en/category/switching-professional-max-xg/products/usw-pro-max-16) |
| $200  | $200 | 1   | [NICGIGA 16-port 1gb Network Switch](https://www.nicgiga.com/products/16-port-2-5g-%E2%9E%95-2-port-10g-sfp-ethernet-switch-nicgiga-18-port-2-5gb-network-switch-unmanaged-plug-play-desktop-or-19-inch-rack-mount-fanless-metal-design) |
| **$4,540** | | | **Estimated Total** |

## Switch Layout

Network port connection layout (unmanaged switch)

| Port | Host     | Purpose | Port | Host       | Purpose |
|:--:|:-----------|:--------|:----:|:-----------|:----|
| 1  | nuc-00     |         | 9    | nuc-02-kvm | |
| 2  | nuc-01     |         | 10   | nuc-03-kvm | | 
| 3  | nuc-02     |         | 11   |            | |
| 4  | nuc-03     |         | 12   |            | |
| 5  | nuc-01-vms |         | 13   |            | |
| 6  | nuc-02-vms |         | 14   |            | |
| 7  | nuc-03-vms |         | 15   | spark-e    | |
| 8  | nuc-01-kvm |         | 16   | uplink     | | 
