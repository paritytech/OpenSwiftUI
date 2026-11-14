#!/usr/bin/env bash
# Unpacks an Alpine root with the headers and libraries the GTK example links against.
# Alpine 3.22 carries musl 1.2.5, the version the static Linux SDK for Swift 6.3 is built on.
#
# musl's own headers are left out. GTK's compiler flags put this root's include directory on
# the search path, and a second copy of the C library's headers there clashes with the SDK's
# ("redefinition of 'iovec'") as soon as a file imports both GTK and Foundation's C modules.
#
#   make-sysroot.sh <x86_64|aarch64> [directory]
#
# Prints the directory. Needs Docker, and an aarch64 binfmt handler for the other architecture.

set -euo pipefail

arch="${1:?usage: make-sysroot.sh <x86_64|aarch64> [directory]}"
case "$arch" in
x86_64) platform=linux/amd64 ;;
aarch64) platform=linux/arm64 ;;
*) echo "unknown architecture: $arch" >&2; exit 2 ;;
esac
sysroot="${2:-$HOME/.cache/openswiftui-gtk/alpine-3.22-$arch}"

rm -rf "$sysroot"
mkdir -p "$sysroot"
docker run --rm --platform "$platform" alpine:3.22 sh -c '
    apk add -q --no-cache musl-dev gcc g++ gtk4.0-dev util-linux-dev util-linux-static >&2 &&
    apk info -qL musl-dev | sed -n "s|^usr/include/|/usr/include/|p" | xargs rm -f &&
    tar -C / -cf - lib usr/include usr/lib usr/share/pkgconfig
' | tar -C "$sysroot" -xf -
echo "$sysroot"
