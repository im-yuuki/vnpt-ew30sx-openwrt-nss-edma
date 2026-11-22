#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
flavor=${1:?Pass nor or ram}
case "$flavor" in nor|ram) ;; *) exit 2 ;; esac
ci="$root/.github/ci"
cd "$root/openwrt-nss-edma"

./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p files
cp -a "$root/overlay/files/." files/
if [[ -n ${FEED_URL:-} ]]; then
	feeds=(target base packages nss)
	if [[ "$flavor" == nor ]]; then feeds+=(luci); fi
	for feed in "${feeds[@]}"; do
		printf '%s/%s/packages.adb\n' "$FEED_URL" "$feed"
	done >>files/etc/apk/repositories.d/distfeeds.list
fi

fragments=("$ci/ew30sx.config" "$ci/ew30sx-$flavor.config")
cat "${fragments[@]}" >.config
make defconfig

while IFS= read -r req; do
	if ! grep -qxF "$req" .config; then
		printf '::error::defconfig did not retain %s\n' "$req" >&2
		exit 1
	fi
done < <(grep -hE '^(CONFIG_[^=]+=|# CONFIG_.* is not set$)' "${fragments[@]}")
