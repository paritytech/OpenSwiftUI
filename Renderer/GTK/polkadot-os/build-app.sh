#!/usr/bin/env bash
# Builds the kitchen sink as an app for polkadotOS (github.com/paritytech/polkadot-os): a
# complete app directory, as its app registry wants one (system-ui/compositor/src/apps.rs there),
# and the same directory as a .tar.gz.
#
#   build-app.sh <x86_64|aarch64> <sysroot> [output directory]
#
# <sysroot> comes from ../alpine/make-sysroot.sh; what else the build needs is said in
# ../alpine/build.sh, which this runs. The output directory is
# ../.build-alpine/<arch>/polkadot-os unless given. In it:
#
#   swiftui-kitchen-sink/                the app directory: app.conf, icon.svg, kitchen-sink
#   swiftui-kitchen-sink-<arch>.tar.gz   the same, to carry to a phone
#
# The program is built for Alpine 3.22 and musl, and links Swift's runtime into itself. Of the
# phone it needs the packages gtk4.0 and libstdc++, and a font.
#
# On a phone, for one user. ~/.local/share/polkadot-os also holds the host service's account
# store and has to stay mode 700 (polkadot-os's AGENTS.md): a plain mkdir -p makes it 755 when
# it is not there yet, hence the chmod.
#
#   sudo apk add gtk4.0 libstdc++
#   mkdir -p ~/.local/share/polkadot-os/apps && chmod 700 ~/.local/share/polkadot-os
#   tar -xzf swiftui-kitchen-sink-aarch64.tar.gz -C ~/.local/share/polkadot-os/apps
#
# Home shows it the next time it is shown. Or in a bundle of your own, packed in a polkadot-os
# checkout from binaries built there:
#
#   tools/phone/bundle.sh pack ... --app <output directory>/swiftui-kitchen-sink \
#       --package gtk4.0 --package libstdc++
#
# It cannot be a line of polkadot-os's release/built-apps as it is: those apps are built from
# source on Alpine aarch64 by the bundle build, and Swift has no toolchain that runs on Alpine.

set -euo pipefail

usage="usage: build-app.sh <x86_64|aarch64> <sysroot> [output directory]"
arch="${1:?$usage}"
sysroot="${2:?$usage}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="$(realpath -m "${3:-$here/../.build-alpine/$arch/polkadot-os}")"
id="$(sed -n 's/^id=//p' "$here/app.conf")"
program="$(sed -n 's/^program=//p' "$here/app.conf")"

built="$("$here/../alpine/build.sh" "$arch" "$sysroot" --product KitchenSink --release | tail -n 1)"
built="$here/../$built"
[[ -x "$built" ]] || { echo "the build left no program at $built" >&2; exit 1; }

app="$output/$id"
rm -rf "$app"
mkdir -p "$app"
install -m 644 "$here/app.conf" "$here/icon.svg" "$app/"
install -m 755 "$built" "$app/$program"

# The same bytes whenever the same program is packed: no owner, no times, a fixed order.
archive="$output/$id-$arch.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -C "$output" -cf - "$id" | gzip -n > "$archive"

echo "$app"
echo "$archive"
