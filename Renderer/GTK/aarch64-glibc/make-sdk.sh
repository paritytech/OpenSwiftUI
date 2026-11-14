#!/usr/bin/env bash
# Builds and installs a Swift SDK for cross-compiling to aarch64 glibc Linux: Arch Linux ARM,
# or any distribution with glibc >= 2.39 and GTK >= 4.14.
#
# The sysroot is the official arm64 Swift image for Ubuntu 24.04 plus the -dev packages the GTK
# host needs. Binaries linked against its glibc 2.39 and GTK 4.14 run on newer versions, not
# the other way round. The Swift runtime comes from the same image, so the image's Swift
# version has to equal the installed toolchain's.
#
#   make-sdk.sh
#
# Prints the installed sysroot. Builds must refer to that path, not to a second copy: the same
# module map seen under two paths is a "redefinition of module" error.
# Needs Docker and an aarch64 binfmt handler.

set -euo pipefail

version="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9.]*\).*/\1/p')"
name="swift-${version}_aarch64-noble-gtk4"
staging="$(mktemp -d "${TMPDIR:-/var/tmp}/swift-sdk.XXXXXX")"
bundle="$staging/$name.artifactbundle"
sysroot="$bundle/sdk/sysroot"
image="openswiftui-gtk-aarch64-sysroot:$version"

docker build --platform linux/arm64 -t "$image" - <<EOF
FROM swift:${version}-noble
RUN apt-get update \\
 && apt-get install -y --no-install-recommends libgtk-4-dev uuid-dev libssl-dev \\
 && rm -rf /var/lib/apt/lists/*
EOF

rm -rf "$bundle"
mkdir -p "$sysroot"
container="$(docker create --platform linux/arm64 "$image")"
trap 'docker rm -f "$container" >/dev/null' EXIT
# /lib is a symlink to usr/lib on Ubuntu; headers, libraries and pkg-config files are all we need.
docker export "$container" | tar -C "$sysroot" -xf - lib usr/include usr/lib usr/share/pkgconfig

# A few -dev symlinks are absolute and would point into the host; make them sysroot-relative.
find "$sysroot" -type l -lname '/*' | while read -r link; do
    target="$(readlink "$link")"
    ln -snf "$(realpath -m --relative-to="$(dirname "$link")" "$sysroot$target")" "$link"
done

# Compute hashes with libcrypto, whose soname differs between distributions (libcrypto.so.3 on
# Ubuntu 24.04, libcrypto.so.4 on Arch Linux ARM). Without the shared-library link name the
# linker takes libcrypto.a, and the executable carries its own copy.
rm "$sysroot/usr/lib/aarch64-linux-gnu/libcrypto.so"

cat > "$bundle/info.json" <<EOF
{
  "schemaVersion": "1.0",
  "artifacts": {
    "swift-${version}_aarch64-noble-gtk4": {
      "type": "swiftSDK",
      "version": "${version}",
      "variants": [{ "path": "sdk" }]
    }
  }
}
EOF
cat > "$bundle/sdk/swift-sdk.json" <<'EOF'
{
  "schemaVersion": "4.0",
  "targetTriples": {
    "aarch64-unknown-linux-gnu": {
      "sdkRootPath": "sysroot",
      "swiftResourcesPath": "sysroot/usr/lib/swift",
      "swiftStaticResourcesPath": "sysroot/usr/lib/swift_static",
      "toolsetPaths": ["toolset.json"]
    }
  }
}
EOF
# The host toolchain's lld links for any architecture; the system ld only for its own.
cat > "$bundle/sdk/toolset.json" <<'EOF'
{
  "schemaVersion": "1.0",
  "swiftCompiler": { "extraCLIOptions": ["-use-ld=lld"] }
}
EOF

swift sdk remove "$name" >/dev/null 2>&1 || true
swift sdk install "$bundle" >&2
rm -rf "$staging"
echo "$HOME/.swiftpm/swift-sdks/$name.artifactbundle/sdk/sysroot"
