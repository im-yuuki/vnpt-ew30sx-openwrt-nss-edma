# OpenWrt for VNPT iGate EW30SX

Experimental firmware for the **EW30SX MP02.1** (IPQ5018, 256 MiB RAM, 32 MiB
SPI-NOR). Board-specific changes live in `patches/`; CI builds the latest
`c3po-tag-8021q` upstream commit and its configured feeds.

| Profile | Output | Purpose |
|---|---|---|
| `nor` | Separate kernel FIT and SquashFS root filesystem | Boots from flash. Includes LuCI over HTTPS and NSS/SQM controls. |
| `ram` | Initramfs FIT | Temporary boot over UART/TFTP for recovery and diagnosis. **Do not flash this FIT.** |

An earlier NOR beta booted from stock U-Boot, accepted LAN SSH, and detected
both radios. The current firmware has not been verified on hardware. Both
profiles include full `wpad-mbedtls` with stock OpenWrt AP/WPS defaults (off,
no key). NSS offload is enabled by default. There is no stock web installer
or sysupgrade image. See the [bring-up notes](docs/ew30sx-ram-boot.md).

## Build on GitHub Actions

On the default branch, go to **Actions → Build EW30SX firmware + signed APK
feeds → Run workflow**. Both profiles use the same upstream commit. CI
stops if a patch fails to apply or a required configuration is dropped,
and updates the submodule pointer after both builds pass.

Each profile has two artifacts, firmware and its signed kmod feed, retained
for three days. The firmware artifact includes checksums, the kernel
configuration, the package manifest and the source revisions. Successful
default-branch builds are published automatically to
[GitHub Pages](https://im-yuuki.github.io/vnpt-ew30sx-openwrt-nss-edma/).
The generated `gh-pages` snapshot keeps the last three builds without
retaining old binaries in its branch history. Enable `publish_release`
to also publish the raw images and matching feed archives as a prerelease.
Set `EW30SX_PAGES_URL` if using a custom Pages URL.

Images use the official OpenWrt snapshot feeds for userspace and the
build-specific kmod index at `/<tag>/<nor|ram>/apk/target/packages.adb`.
Do not mix kmods between builds or profiles. Save the matching feed archive
if you need it after a build is removed from Pages.

## Build locally

Use a **fresh clone** and a native Linux host toolchain with the
[OpenWrt build prerequisites][prereqs]. Build one profile per checkout
to keep outputs and signing keys separate:

```bash
git submodule update --init -- openwrt-nss-edma
for patch in "$PWD"/patches/*.patch; do
    git -C openwrt-nss-edma apply --index "$patch" || exit
done
bash .github/ci/configure.sh nor
cd openwrt-nss-edma
make download -j"$(nproc)"
make -j"$(nproc)"
make package/index
bash ../.github/ci/collect.sh nor ../out/nor
```

Use `ram` in place of `nor` for the RAM profile. The commands above use
the recorded submodule commit. Pass `--remote` to `git submodule update`
to build from the upstream branch tip as CI does.

[prereqs]: https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
