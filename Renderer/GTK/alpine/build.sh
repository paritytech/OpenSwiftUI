#!/usr/bin/env bash
# Cross-builds the example for Alpine (musl) from a glibc machine.
#
#   build.sh <x86_64|aarch64> <sysroot> [swift build arguments]
#
# <sysroot> comes from make-sysroot.sh. Needs the Swift SDK for Static Linux that matches the
# installed toolchain (https://www.swift.org/install/linux), which supplies Swift's runtime and
# Foundation for musl as static libraries.
#
# The SDK only links fully static executables, and a static musl executable cannot dlopen, so
# it could never load GTK or a GPU driver. This script therefore compiles with SwiftPM and links
# by hand: Swift's runtime statically, musl, GTK4, Cairo and Pango dynamically from the sysroot.
# The result is .build-alpine/<arch>/ExampleApp and needs only Alpine's gtk4.0 package.

set -euo pipefail

arch="${1:?usage: build.sh <x86_64|aarch64> <sysroot> [swift build arguments]}"
sysroot="$(realpath "${2:?usage: build.sh <x86_64|aarch64> <sysroot> [swift build arguments]}")"
shift 2

cd "$(dirname "${BASH_SOURCE[0]}")/.."

swift_binary="$(readlink -f "$(command -v swift)")"
if [[ "$(basename "$swift_binary")" == swiftly ]]; then
    toolchain="$(swiftly use --print-location)/usr/bin"
else
    toolchain="$(dirname "$swift_binary")"
fi
sdk="$(compgen -G "$HOME/.swiftpm/swift-sdks/swift-*_static-linux-*.artifactbundle/*/swift-linux-musl/musl-*.sdk/$arch" | head -n 1)"
[[ -d "$sdk" ]] || { echo "the Swift SDK for Static Linux is not installed" >&2; exit 1; }
runtime="$sdk/usr/lib/swift_static/linux-static"

scratch=".build-alpine/$arch"
support="$scratch/support"
objects="$scratch/$arch-swift-linux-musl/debug"

export OPENSWIFTUI_OPENATTRIBUTESHIMS_ATTRIBUTEGRAPH=0
export OPENSWIFTUI_OPENATTRIBUTESHIMS_COMPUTE=1
export OPENSWIFTUI_OPENATTRIBUTESHIMS_COMPUTE_SOURCE_VERSION="${OPENSWIFTUI_OPENATTRIBUTESHIMS_COMPUTE_SOURCE_VERSION:-0.6.4-bugfix.2}"
export OPENSWIFTUI_LIB_SWIFT_PATH="$sdk/usr/lib/swift_static"
# GTK's headers and link flags come from the sysroot, not from this machine.
export PKG_CONFIG_SYSROOT_DIR="$sysroot"
export PKG_CONFIG_LIBDIR="$sysroot/usr/lib/pkgconfig:$sysroot/usr/share/pkgconfig"
export PKG_CONFIG_PATH="$PKG_CONFIG_LIBDIR"

# The two headers Compute needs and the SDK lacks. They go to every target; the sysroot's
# other headers reach only the targets that use GTK, through its compiler flags.
mkdir -p "$support/include" "$support/lib"
ln -sfn "$sysroot/usr/include/uuid" "$support/include/uuid"
cp alpine/execinfo.h "$support/include/execinfo.h"

# SwiftPM compiles everything and then fails its own link step, which insists on a static
# executable. Its object list for that step is what gets linked below; an object missing from
# disk means the failure was a compile error instead.
object_list="$objects/ExampleApp.product/Objects.LinkFileList"
# The plan is made afresh each time: in the cross builds SwiftPM's cached plan did not pick up
# a source file added to the package the example depends on.
swift build --swift-sdk "$arch-swift-linux-musl" --scratch-path "$scratch" --product ExampleApp \
    --disable-build-manifest-caching \
    -Xcxx -include -Xcxx cstdint -Xcc -I"$PWD/$support/include" "$@" || true
[[ -f "$object_list" ]] || { echo "swift build produced no object list" >&2; exit 1; }
while read -r object; do
    [[ -f "$object" ]] || { echo "swift build failed before linking: $object is missing" >&2; exit 1; }
done < "$object_list"

headers="$scratch/checkouts/Compute/Submodules/swift-runtime-headers"
"$toolchain/clang++" --target="$arch-swift-linux-musl" --sysroot="$sdk" -std=c++20 -fPIC -O1 \
    -DCOMPILED_WITH_SWIFT -DPURE_BRIDGING_MODE \
    -isystem "$headers/include" -isystem "$headers/stdlib/include" -isystem "$headers/stdlib/public/SwiftShims" \
    -c support/Demangle.cpp -o "$support/lib/Demangle.o"

# Swift objects name the libraries they need in a section the ELF linker ignores.
autolink="$support/autolink.txt"
xargs "$toolchain/swift-autolink-extract" -o "$autolink" < "$object_list"
# GTK and uuid are linked explicitly below; libswiftDemangle is replaced by Demangle.o.
sed -i -e '/^-lgtk-4$/d' -e '/^-lswiftDemangle$/d' -e '/^-luuid$/d' "$autolink"

gtk_libs="$(PKG_CONFIG_SYSROOT_DIR="$sysroot" pkg-config --libs-only-l gtk4)"

# SwiftPM names an executable's entry point <module>_main and aliases it when it links.
# FoundationNetworking (AsyncImage) and libcrypto (Compute's hashing) are not autolinked.
# shellcheck disable=SC2086
"$toolchain/clang" --target="$arch-alpine-linux-musl" --sysroot="$sysroot" -fuse-ld=lld -pie \
    -o "$scratch/ExampleApp" \
    "$runtime/$arch/swiftrt.o" "@$object_list" "$support/lib/Demangle.o" \
    -Wl,--defsym,main=ExampleApp_main \
    -L"$runtime" -L"$sysroot/usr/lib" -L"$sdk/usr/lib" \
    -Wl,--start-group "@$autolink" -lswiftCore -lswift_RegexParser -ldispatch -lBlocksRuntime \
    -lFoundationNetworking -l_CFURLSessionInterface -Wl,--end-group \
    "$sysroot/usr/lib/libuuid.a" \
    "$sdk/usr/lib/libcurl.a" "$sdk/usr/lib/libssl.a" "$sdk/usr/lib/libcrypto.a" "$sdk/usr/lib/libz.a" \
    "$sdk/usr/lib/libc++.a" "$sdk/usr/lib/libc++abi.a" \
    $gtk_libs -lstdc++ -lm -lpthread -ldl -Wl,--export-dynamic
echo "$scratch/ExampleApp"
