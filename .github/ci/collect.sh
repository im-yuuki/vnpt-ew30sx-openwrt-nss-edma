#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

flavor=${1:?Pass nor or ram}
dest=${2:?Pass the output directory}
target=bin/targets/qualcommax/ipq50xx
feeds=bin/packages/aarch64_cortex-a53
prefix=openwrt-qualcommax-ipq50xx-vnpt_ew30sx
required=(apk-mbedtls dnsmasq dropbear firewall4 nftables odhcp6c odhcpd-ipv6only
	ppp-mod-pppoe kmod-ath11k-ahb kmod-gpio-button-hotplug kmod-leds-gpio
	ath11k-firmware-ipq5018-qcn6122 nss-tools-dwmac nss-firmware-ipq50xx
	squashfs-tools-unsquashfs)
case "$flavor" in
nor)
	images=("$prefix-nor-squashfs-kernel.itb" "$prefix-nor-squashfs-rootfs.squashfs")
	required+=(luci-ssl uhttpd wpad-mbedtls)
	;;
ram)
	images=("$prefix-initramfs-uImage.itb")
	required+=(iperf3 wpad-basic-mbedtls)
	;;
*) exit 2 ;;
esac

mkdir -p "$dest"/{firmware,apk}
for image in "${images[@]}"; do
	test -s "$target/$image"
	cp "$target/$image" "$dest/firmware/"
done
if [[ "$flavor" == nor ]]; then
	(( $(stat -c %s "$target/${images[0]}") <= 5 * 1024 * 1024 ))
	(( $(stat -c %s "$target/${images[1]}") <= 19968 * 1024 ))
fi

# The target-level manifest omits profile-only packages. CI builds one profile
# per clean checkout, so the single assembled device rootfs is authoritative.
shopt -s nullglob
roots=(build_dir/target-*/linux-qualcommax_ipq50xx/target-dir-*)
kconfigs=(build_dir/target-*/linux-qualcommax_ipq50xx/linux-*/.config)
if [[ ${#roots[@]} != 1 || ${#kconfigs[@]} != 1 ]]; then
	printf '::error::expected one EW30SX rootfs and one kernel config\n' >&2
	exit 1
fi
for sym in DWMAC_IPQ5018 NET_DSA_QCA8K SPI_QUP MTD_SPI_NOR MTD_SPLIT_SQUASHFS_ROOT \
	QCOM_Q6V5_WCSS_SEC QCOM_TSENS QCOM_WDT SQUASHFS_XZ JFFS2_FS LEDS_TRIGGER_NETDEV; do
	grep -qxF "CONFIG_$sym=y" "${kconfigs[0]}" || { echo "::error::missing kernel config: $sym"; exit 1; }
done
cp "${kconfigs[0]}" "$dest/firmware/kernel.config"

manifest="$dest/firmware/$flavor.manifest"
staging_dir/host/bin/apk --root "${roots[0]}" --no-logfile \
	list --quiet --manifest --no-network --repositories-file /dev/null |
	sort | sed 's/ / - /' >"$manifest"
for pkg in "${required[@]}"; do
	grep -q "^$pkg - " "$manifest" || { echo "::error::missing image package: $pkg"; exit 1; }
done
if [[ "$flavor" == nor ]] && grep -q '^wpad-basic-mbedtls - ' "$manifest"; then
	echo "::error::the NOR image must not contain the basic wpad variant"
	exit 1
fi
for pkg in kmod-tun kmod-wireguard; do
	compgen -G "$target/packages/$pkg-*.apk" >/dev/null
done

cp "$target"/{config,feeds,version}.buildinfo "$dest/firmware/"
printf 'wrapper=%s\nopenwrt=%s\nprofile=%s\n' \
	"$(git -C .. rev-parse HEAD)" "$(git rev-parse HEAD)" "$flavor" >"$dest/firmware/source.txt"
(cd "$dest/firmware" && sha256sum -- "${images[@]}" >sha256sums)

for feed in target base luci packages nss; do
	if [[ "$feed" == target ]]; then src="$target/packages"; else src="$feeds/$feed"; fi
	# RAM deliberately has no LuCI; it may not build any LuCI packages.
	if [[ "$flavor:$feed" == ram:luci && ! -s "$src/packages.adb" ]]; then continue; fi
	test -s "$src/packages.adb"
	mkdir -p "$dest/apk/$feed"
	cp "$src"/packages.adb "$src"/*.apk "$dest/apk/$feed/"
done
test -s public-key.pem
cp public-key.pem "$dest/apk/"
