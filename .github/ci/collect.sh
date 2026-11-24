#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

flavor=${1:?Pass nor or ram}
dest=${2:?Pass the output directory}
target=bin/targets/qualcommax/ipq50xx
prefix=openwrt-qualcommax-ipq50xx-vnpt_ew30sx
# firewall4 requires the concrete nftables-json package. nftables is just
# the name provided by that package, not a manifest entry.
required=(apk-mbedtls dnsmasq dropbear firewall4 nftables-json odhcp6c odhcpd-ipv6only
	ppp-mod-pppoe kmod-qca-nss-drv-pppoe kmod-ath11k-ahb kmod-gpio-button-hotplug kmod-leds-gpio
	ath11k-firmware-ipq5018-qcn6122 nss-tools-dwmac nss-firmware-ipq50xx
	squashfs-tools-unsquashfs wpad-mbedtls)
case "$flavor" in
nor)
	images=("$prefix-nor-squashfs-kernel.itb" "$prefix-nor-squashfs-rootfs.squashfs")
	required+=(luci-ssl uhttpd luci-app-nss luci-app-sqm nssinfo sqm-scripts-nss)
	;;
ram)
	images=("$prefix-initramfs-uImage.itb")
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
	awk -v pkg="$pkg" '$1 == pkg && $2 == "-" { found = 1 } END { exit !found }' "$manifest" ||
		{ echo "::error::missing image package: $pkg"; exit 1; }
done
if grep -q '^wpad-basic-mbedtls - ' "$manifest"; then
	echo "::error::the $flavor image must not contain the basic wpad variant"
	exit 1
fi
while IFS= read -r pkg; do
	compgen -G "$target/packages/$pkg-*.apk" >/dev/null ||
		{ echo "::error::missing signed package: $pkg"; exit 1; }
done < <(sed -nE 's/^CONFIG_PACKAGE_(kmod-[^=]+)=m$/\1/p' ../.github/ci/ew30sx.config)

cp "$target"/{config,feeds,version}.buildinfo "$dest/firmware/"
printf 'wrapper=%s\nopenwrt=%s\nprofile=%s\n' \
	"$(git -C .. rev-parse HEAD)" "$(git rev-parse HEAD)" "$flavor" >"$dest/firmware/source.txt"
(cd "$dest/firmware" && sha256sum -- "${images[@]}" >sha256sums)

test -s "$target/packages/packages.adb"
mkdir -p "$dest/apk/target"
cp "$target"/packages/{packages.adb,*.apk} "$dest/apk/target/"
test -s public-key.pem
cp public-key.pem "$dest/apk/"
