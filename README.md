<!---
NOTE: AUTO-GENERATED FILE
to edit this file, instead edit its template at: ./ci/templates/README.md.j2
-->
<div align="center">


## Glants OpenWrt Firmwares

_Collection of firmwares for routers to fight against censorship_

</div>

<div align="center">

![GitHub Repo stars](https://img.shields.io/github/stars/mglants/glantswrt?style=for-the-badge)
![GitHub forks](https://img.shields.io/github/forks/mglants/glantswrt?style=for-the-badge)
![GitHub Workflow Status (with event)](https://img.shields.io/github/actions/workflow/status/mglants/glantswrt/openwrt-builder-ib.yml?style=for-the-badge&label=OpenWRT%20Builder)

</div>

---

## About

This repository contains a custom **OpenWrt firmware** focused on reliability, reproducibility, and autonomous operation in constrained network environments.
The goal is to provide a ready-to-use system that requires minimal user configuration while remaining flexible and maintainable over time.

- Nikki is main software for VLESS subscriptions
- Some packages are added to make VPN tunnels
- Minimal software packs for routers
- For LTE/4G routers software are included
- No custom build or kernel, just repacking
- Suggestions are welcomed

The firmware includes a curated set of networking and management packages:

- `nikki`
- `luci-app-nikki`
- `luci`
- `kmod-amneziawg`
- `luci-proto-amneziawg`
- `amneziawg-tools`
- `luci-proto-wireguard`
- `wireguard-tools`

---


### Firmwares

Vendor | Router | OpenWrt | Packages | Release
--- | --- | --- | --- | ---
cudy | **tr3000(TR30)** | v24.10.5 | [22](https://github.com/mglants/glantswrt/blob/main/devices/tr3000/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=tr3000-&expanded=true)
cudy | **wr3000(WBR3000UAX)** | v24.10.5 | [8](https://github.com/mglants/glantswrt/blob/main/devices/wr3000/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=wr3000-&expanded=true)
cudy | **wr3000h** | v24.10.5 | [8](https://github.com/mglants/glantswrt/blob/main/devices/wr3000h/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=wr3000h-&expanded=true)
cudy | **wr3000s** | v24.10.5 | [8](https://github.com/mglants/glantswrt/blob/main/devices/wr3000s/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=wr3000s-&expanded=true)
Keenetic | **KN-3510** | v24.10.5 | [8](https://github.com/mglants/glantswrt/blob/main/devices/kn3510/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=kn3510-&expanded=true)
netis | **n6** | v24.10.5 | [21](https://github.com/mglants/glantswrt/blob/main/devices/netisn6/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=netisn6-&expanded=true)
xiaomi | **ax3000t** | v24.10.5 | [8](https://github.com/mglants/glantswrt/blob/main/devices/ax3000t/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=ax3000t-&expanded=true)
Xiaomi | **Redmi AX6000** | v24.10.5 | [8](https://github.com/mglants/glantswrt/blob/main/devices/ax6000/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=ax6000-&expanded=true)
xiaomi | **ax6s** | v24.10.5 | [8](https://github.com/mglants/glantswrt/blob/main/devices/ax6s/packages.txt) | [download](https://github.com/mglants/glantswrt/releases?q=ax6s-&expanded=true)
