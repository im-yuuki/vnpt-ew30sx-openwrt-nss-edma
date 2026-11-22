# Build outputs

Download `firmware-<tag>-<nor|ram>` and `kmods-<tag>-<nor|ram>` from the
repository's Actions tab (three-day retention), or get the raw images and
matching APK feed archives from an optional prerelease. GitHub Pages carries the
three most recent published builds; archive the matching feed if you need it
after the build ages out of Pages.
Each layout (`nor`, `ram`) has its own firmware, build metadata, signed APK
indexes and public key. Keep them paired with the exact run and attempt.
Firmware and package binaries are not tracked on the source branch.
Signing private keys are never published.
