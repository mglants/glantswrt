# AX3000T — OpenWrt U-Boot layout

This device profile builds the AX3000T `xiaomi_mi-router-ax3000t-ubootmod` image. The existing `devices/ax3000t` profile remains the stock-layout build.

Important: this U-Boot-layout image is not a drop-in sysupgrade for a stock-layout router. Convert the router to OpenWrt U-Boot first, following the [official AX3000T guide](https://openwrt.org/toh/xiaomi/ax3000t#change_to_openwrt_u-boot). Do not flash this profile to an unconverted stock-layout device. OpenWrt also notes that RD03v2 is not supported by this device target.
