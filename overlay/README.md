# Image overlay

`files/` is copied over the source tree's OpenWrt `files/` directory in a
fresh build checkout. `configure.sh` adds official userspace snapshots and,
for default-branch CI, the signed kmod index for the matching Pages build.
Board-specific kernel, network and Wi-Fi setup lives in `patches/`, not here.
