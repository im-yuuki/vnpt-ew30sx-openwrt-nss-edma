#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

site=${1:?Pass the Pages directory}
tag_re='^ew30sx-[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]+-a[0-9]+$'
keep=3
mkdir -p -- "$site"

if [[ $# -gt 1 ]]; then
	incoming=${2:?Pass the new build directory}
	tag=${3:?Pass the build tag}
	[[ "$tag" =~ $tag_re ]]
	for flavor in nor ram; do
		test -s "$incoming/$flavor/apk/public-key.pem"
		test -s "$incoming/$flavor/apk/target/packages.adb"
		test -s "$incoming/$flavor/firmware/sha256sums"
		(cd "$incoming/$flavor/firmware" && sha256sum --strict -c sha256sums)
	done
	# A deployment retry may find this tag already on the branch. Never
	# replace a published URL with a different APK signing key or payload.
	if [[ -e "$site/$tag" ]]; then
		diff -qr -- "$site/$tag" "$incoming"
	fi
fi

shopt -s nullglob
tags=()
for dir in "$site"/*; do
	name=${dir##*/}
	if [[ -d "$dir" && "$name" =~ $tag_re ]]; then tags+=("$name"); fi
done
if [[ -n ${tag:-} && ! -e "$site/$tag" ]]; then tags+=("$tag"); fi
if (( ${#tags[@]} > 0 )); then
	# Run number first, then attempt. Rerunning an old job on a new date
	# must not bump it ahead of runs with a higher run number.
	mapfile -t tags < <(printf '%s\n' "${tags[@]}" | sort -t- -k3,3nr -k4.2,4nr)
fi
if [[ -n ${tag:-} ]]; then
	found=false
	for name in "${tags[@]:0:keep}"; do
		if [[ "$name" == "$tag" ]]; then found=true; fi
	done
	if ! "$found"; then
		echo "::error::$tag is older than the three retained Pages builds" >&2
		exit 1
	fi
	if [[ ! -e "$site/$tag" ]]; then cp -a -- "$incoming" "$site/$tag"; fi
fi
for name in "${tags[@]:keep}"; do
	rm -rf -- "$site/$name"
done

prefix=openwrt-qualcommax-ipq50xx-vnpt_ew30sx
{
	cat <<'HTML'
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>EW30SX OpenWrt builds</title>
<h1>EW30SX OpenWrt builds</h1>
<p>Up to three published builds are kept here. Use signed packages only with the matching build and profile. Never flash the RAM FIT or use the split NOR files as a sysupgrade image.</p>
HTML
	if (( ${#tags[@]} == 0 )); then
		printf '<p>No firmware builds have been published yet.</p>\n'
	fi
	for name in "${tags[@]:0:keep}"; do
		printf '<h2>%s</h2>\n<ul>\n' "$name"
		printf '<li>NOR: <a href="%s/nor/firmware/%s-nor-squashfs-kernel.itb">kernel FIT</a> · <a href="%s/nor/firmware/%s-nor-squashfs-rootfs.squashfs">rootfs</a>' \
			"$name" "$prefix" "$name" "$prefix"
		printf ' · <a href="%s/nor/firmware/sha256sums">SHA-256</a> · <a href="%s/nor/apk/target/packages.adb">APK target index</a></li>\n' \
			"$name" "$name"
		printf '<li>RAM: <a href="%s/ram/firmware/%s-initramfs-uImage.itb">RAM FIT</a>' "$name" "$prefix"
		printf ' · <a href="%s/ram/firmware/sha256sums">SHA-256</a> · <a href="%s/ram/apk/target/packages.adb">APK target index</a></li>\n</ul>\n' \
			"$name" "$name"
	done
	printf '</html>\n'
} >"$site/index.html"
touch "$site/.nojekyll"

# upload-pages-artifact does not support links, and published sites are
# limited to 1 GB. Check before committing anything to the storage branch.
if [[ -n "$(find "$site" -type l -print -quit)" ]]; then
	echo "::error::Pages snapshot contains a symbolic link" >&2
	exit 1
fi
if (( $(du -sb -- "$site" | cut -f1) > 1000000000 )); then
	echo "::error::Pages snapshot exceeds 1 GB" >&2
	exit 1
fi
