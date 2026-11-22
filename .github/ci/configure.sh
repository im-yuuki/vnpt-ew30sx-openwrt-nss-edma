#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
flavor=${1:?Pass nor or ram}
case "$flavor" in nor|ram) ;; *) exit 2 ;; esac
ci="$root/.github/ci"
cd "$root/openwrt-nss-edma"

./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p files/etc/apk/repositories.d
{
	# Official userspace feeds are compatible; official target/kmod indexes are not.
	if [[ -n ${FEED_URL:-} ]]; then printf '%s/packages.adb\n' "$FEED_URL"; fi
	for feed in base luci packages routing telephony video; do
		printf 'https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53/%s/packages.adb\n' "$feed"
	done
} >files/etc/apk/repositories.d/distfeeds.list

fragments=("$ci/ew30sx.config" "$ci/ew30sx-$flavor.config")
cat "${fragments[@]}" >.config
make defconfig

while IFS= read -r req; do
	if ! grep -qxF "$req" .config; then
		printf '::error::defconfig did not retain %s\n' "$req" >&2
		exit 1
	fi
done < <(grep -hE '^(CONFIG_[^=]+=|# CONFIG_.* is not set$)' "${fragments[@]}")
