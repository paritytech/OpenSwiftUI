#!/usr/bin/env bash
# Cross-builds the example for aarch64 glibc Linux with the SDK from make-sdk.sh.
#
#   build.sh [swift build arguments]
#
# Swift's runtime and Foundation are linked statically, so the device needs only gtk4.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift_binary="$(readlink -f "$(command -v swift)")"
if [[ "$(basename "$swift_binary")" == swiftly ]]; then
    toolchain="$(swiftly use --print-location)/usr/bin"
else
    toolchain="$(dirname "$swift_binary")"
fi
version="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p')"
sysroot="$HOME/.swiftpm/swift-sdks/swift-${version}_aarch64-noble-gtk4.artifactbundle/sdk/sysroot"
[[ -d "$sysroot" ]] || { echo "run aarch64-glibc/make-sdk.sh first" >&2; exit 1; }

export OPENSWIFTUI_OPENATTRIBUTESHIMS_ATTRIBUTEGRAPH=0
export OPENSWIFTUI_OPENATTRIBUTESHIMS_COMPUTE=1
export OPENSWIFTUI_OPENATTRIBUTESHIMS_COMPUTE_SOURCE_VERSION="${OPENSWIFTUI_OPENATTRIBUTESHIMS_COMPUTE_SOURCE_VERSION:-0.6.4-bugfix.2}"
# The static resource directory, because --static-swift-stdlib compiles against it.
export OPENSWIFTUI_LIB_SWIFT_PATH="$sysroot/usr/lib/swift_static"
# GTK's headers and link flags come from the sysroot, not from this machine.
export PKG_CONFIG_SYSROOT_DIR="$sysroot"
export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig:$sysroot/usr/share/pkgconfig:$sysroot/usr/lib/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"

scratch=.build-aarch64-glibc
support="$scratch/support"
mkdir -p "$support"

# Compute asks for -lswiftDemangle. This archive is found before the toolchain's shared
# library, which would drag in a second, dynamic copy of the Swift runtime.
swift package --scratch-path "$scratch" resolve
headers="$scratch/checkouts/Compute/Submodules/swift-runtime-headers"
"$toolchain/clang++" --target=aarch64-unknown-linux-gnu --sysroot="$sysroot" -std=c++20 -fPIC -O1 \
    -DCOMPILED_WITH_SWIFT -DPURE_BRIDGING_MODE \
    -isystem "$headers/include" -isystem "$headers/stdlib/include" -isystem "$headers/stdlib/public/SwiftShims" \
    -c support/Demangle.cpp -o "$support/Demangle.o"
rm -f "$support/libswiftDemangle.a"
"$toolchain/llvm-ar" rcs "$support/libswiftDemangle.a" "$support/Demangle.o"

swift build --swift-sdk aarch64-unknown-linux-gnu --scratch-path "$scratch" --static-swift-stdlib \
    -Xcxx -include -Xcxx cstdint -Xlinker -L"$PWD/$support" "$@"
echo "$(swift build --swift-sdk aarch64-unknown-linux-gnu --scratch-path "$scratch" "$@" --show-bin-path)/ExampleApp"
