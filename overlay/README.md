# Image overlay

`files/` is copied over the source tree's OpenWrt `files/` directory in a
fresh build checkout. The APK list suppresses rolling snapshot feeds; CI
adds matching feeds when GitHub Pages is selected. Board-specific kernel,
network and Wi-Fi setup lives in `patches/`, not in this overlay.
