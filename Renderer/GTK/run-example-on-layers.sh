#!/usr/bin/env bash
# Builds the example with the layer host and shows it through a layer compositor: the app
# sends layers instead of drawing, and the compositor process draws them in a window.
#
#   run-example-on-layers.sh <LayerKit package directory>
#
# The directory is a checkout of the package that provides LayerKit and its reference
# compositor (layer-compositor). Needs Swift 6.3 and the gtk4, uuid and openssl development
# files. Close the window to stop; the script also ends when the app does.

set -euo pipefail

layerkit="$(realpath "${1:?usage: run-example-on-layers.sh <LayerKit package directory>}")"
cd "$(dirname "${BASH_SOURCE[0]}")"

(cd "$layerkit" && swift build --product layer-compositor)

# Compute as the graph engine, and the toolchain's libraries on the link and runtime paths.
source ../Stdout/configure-env.sh

# The package only gains the layer host when it is told where LayerKit is.
export OPENSWIFTUI_LAYERKIT_PATH="$layerkit"
# Compute 0.6.4 uses std::uint64_t without <cstdint>; libstdc++ 16 no longer includes it
# transitively. Without --disable-build-manifest-caching a source file added to the package
# since the last build is not compiled.
swift build --disable-build-manifest-caching -Xcxx -include -Xcxx cstdint --product ExampleApp

export LAYER_COMPOSITOR_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/layer-compositor-example-$$"
"$layerkit/.build/debug/layer-compositor" --window &
compositor=$!
app=
trap 'kill "$compositor" $app 2>/dev/null || true; rm -f "$LAYER_COMPOSITOR_SOCKET"' EXIT

for _ in $(seq 50); do
    [[ -S "$LAYER_COMPOSITOR_SOCKET" ]] && break
    sleep 0.1
done
[[ -S "$LAYER_COMPOSITOR_SOCKET" ]] || { echo "the compositor did not start" >&2; exit 1; }

OPENSWIFTUI_HOST=layers .build/debug/ExampleApp &
app=$!
# Whichever ends first ends the other, through the trap.
wait -n "$compositor" "$app"
