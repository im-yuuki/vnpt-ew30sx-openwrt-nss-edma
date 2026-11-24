# EW30SX bring-up: RAM and split NOR

The board observations below are from the pre-refactor images. The wrapper
keeps the same partition boundaries and calibration path while CI follows
the configured upstream branch. Both profiles include full `wpad-mbedtls`
for optional WPS and 802.11s. APs and WPS keep stock OpenWrt defaults (off,
no key). The NOR build includes HTTPS LuCI and NSS/SQM controls.
NSS offload is on by default and still needs on-device validation.
The shared board DTS stays at the rated 1008 MHz; it maps the system LEDs to
boot/running/failsafe, the green WAN LED to link/activity, and the Wi-Fi LED
to activity on the first registered PHY.

The `vnpt_ew30sx` profile builds an ARM64 FIT with an embedded initramfs. Do
not write this FIT to flash or save changes to the U-Boot environment. Keep
UART attached (115200 8N1) and use an isolated bench connection. The separate
`vnpt_ew30sx-nor` profile builds the split NOR beta described below.

Build with the EW30SX device selected and initramfs enabled. The OpenWrt
`packages` feed must be available and its `squashfs-tools` recipe installed
with XZ support enabled for `squashfs-tools-unsquashfs`. Retain the 256 MiB
low-memory NSS profile and NSS firmware 12.2.

## Boot and check the jacks

Stock U-Boot's ARM64 handoff was verified with the first RAM build. Keep the
PC cable in the **WAN-labeled jack** for TFTP. With the bench TFTP server
already configured in U-Boot, load the BDF compatibility test build:

```text
tftpboot 0x44000000 yuuki/ew3.itb
bootm 0x44000000#config@mp02.1
```

After OpenWrt boots, move the PC cable to the **LAN-labeled jack** and renew
the PC's DHCP lease. The WAN jack is GMAC0/PHY7 and uses the firewalled WAN
DHCP client. The expected LAN path is AR8337 port 3 → CPU port 6 → GMAC1 →
`br-lan`. The second RAM build probed the switch at MDIO `0x11`, brought up
the CPU link at 1 Gbps, and answered ping through the LAN-labeled jack.
Still verify LAN DHCP with WAN disconnected, port 3 carrier on cable
unplug/replug, and WAN isolation (no LAN DHCP or management access).

This build keeps Ethernet on the Linux host path. Verify both jacks and
routed traffic first; a local `iperf3` session terminating on the router does
not demonstrate forwarding or NSS acceleration. If LAN is unavailable,
diagnose over UART, or reboot and load `yuuki/ew.itb` instead. That first
build uses the WAN-labeled jack as its only management LAN.

## First-boot checks

- Confirm the running model and 256 MiB RAM bank over UART. Expect only `0:ART`
  and `0:WIFIFW` as flash partitions. Do not invoke installation or flash tools.
- Look for `EW30SX: factory data staged in RAM for both radios`. If staging
  fails, look for `factory data unavailable or invalid; not loading ath11k`.
  The stock MP02 layout supplies 128 KiB calibration slices from ART
  (`0x1000` for IPQ5018, `0x26800` for QCN6122) and BDFs from the WIFIFW
  SquashFS (`bdwlan.b10` and `qcn6122/bdwlan.b60`). The FIT carries neither.
  The stock XZ options are incompatible with the kernel mount path;
  `unsquashfs` reads only those two entries into RAM. Both stock BDFs use
  legacy axis value `3` at `0x45c`, which triggers the
  [`phyrf_bdf.c:6245` assertion with WLAN.HK.2.7.0.1][bdf-axis].
  After checking the BDF header, size and XOR checksum, staging translates
  that field to `0` and updates the checksum at `0x0a` in the RAM copies
  only. All other BDF bytes and both ART slices remain unchanged.
  The NOR driver uses only JEDEC ID and dedicated four-byte reads.
- Expect the 2.4 GHz IPQ5018 and one 5 GHz QCN6122 phy only. Leave network
  interfaces on the radios disabled until the logs confirm calibration and
  firmware readiness for both, with no recurring WCSS crash. The ignored
  QMI type 10 request is for AFC, distinct from BDF and calibration memory.
  Do not change the carveouts to resolve the BDF assertion. The QCN6122
  M3 executable uses the shared `m3-region`. Verify regulatory settings
  and test each band separately before using the radios outside the bench.

`ew3.itb` was verified over UART and SSH on the board: the IPQ5018 and
QCN6122 registered as 2.4 GHz and 5 GHz PHYs, respectively. At 112 seconds
of uptime, WCSS was running with no crash or axis assertion in the kernel
log. The QMI AFC warning remained. Both default APs were still disabled;
association and RF performance were not tested.

Do not include raw kernel logs, factory blobs, or hardware identifiers in shared
reports; extract and sanitize the relevant status lines.

## Split NOR beta

Stock `bootipq` selects `config@mp02.1` from `0:HLOS`
(`[0x220000, 0x720000)`, 5 MiB). The separate `rootfs` partition is
`[0x720000, 0x1b20000)` (20 MiB). `rootfs_data` is carved from the tail of
the installed SquashFS; its stock offset is not fixed.

Select only `vnpt_ew30sx-nor`, enable per-device SquashFS and disable
initramfs for this build. The profile produces two files in
`bin/targets/qualcommax/ipq50xx/`:

- `*-vnpt_ew30sx-nor-squashfs-kernel.itb`: kernel-only ARM64/LZMA FIT
  for HLOS, capped at 5 MiB.
- `*-vnpt_ew30sx-nor-squashfs-rootfs.squashfs`: XZ SquashFS with an
  erase-aligned JFFS2 marker, leaving at least 512 KiB for `rootfs_data`.

The NOR DTS exposes only those two OS partitions and ART and WIFIFW, all
read-only under Linux. In this kernel, the `rootfs` splitter registers the
JFFS2 tail as a separate writable `rootfs_data` partition. The NOR profile
does not contain a factory-web image or a sysupgrade installer. Never force
sysupgrade.

Wi-Fi staging uses the firmware loader's custom path under `/tmp`, not the
persistent overlay. The path is set only after both radios' factory data
pass validation. Packaged executable firmware still comes from
`/lib/firmware`. Check that staging succeeds again on the second boot.

The raw pair is for bench validation, not a flash recipe. Do not TFTP-boot
the NOR kernel alone against the stock rootfs: it can select that rootfs.
To test the ARM64/LZMA handoff separately, TFTP-load `yuuki/ew-lz-ram.itb`
and use the same address and `bootm` configuration as `ew3.itb`. It has the
same kernel, initramfs and read-only DTS as `ew3.itb`, recompressed for this
test. Do not flash either RAM FIT.

The first board install of the NOR beta passed a stock U-Boot autoboot:
`bootipq` loaded the ARM64/LZMA FIT from HLOS. Read-back SHA-256 matched the
kernel FIT and immutable SquashFS payload. The first boot initially used
tmpfs while JFFS2 initialized, then switched to JFFS2 `rootfs_data` with
9.75 MiB allocated. Only `rootfs_data` was writable among the exposed MTD
devices. LAN SSH worked, both PHYs registered, and the firmware loader used
the tmpfs staging path. Both APs remained disabled.

Persistence and Wi-Fi staging across a second boot, WAN isolation and routed
traffic, LED/button behavior, factory MAC sourcing, and stock recovery are
still unverified. Both radios registering is not proof of association, DFS,
or sustained traffic. Leave both APs disabled until antennas are attached,
and set the regulatory country before testing RF. Do not substitute Xiaomi
factory data or enable NSS offload using another board's switch configuration.

[bdf-axis]: https://github.com/openwrt/firmware_qca-wireless/commit/acf37292d2c1c27930b4d9ba58276b599706910d
