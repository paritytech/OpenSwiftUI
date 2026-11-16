#!/usr/bin/env bash
# Runs kitchen sink screens through a layer compositor that draws offscreen, with a scripted
# finger and with the app's main thread blocked at chosen moments, and checks the pictures.
#
#   check-layers.sh <LayerKit package directory> [check ...]
#
# The directory is a checkout of the package that provides LayerKit and its reference
# compositor (layer-compositor). Without names, every check is run. What each check expects is
# in support/layer-checks.py; the screens are in KitchenSink/CheckScreens.swift. Needs Swift
# 6.3, the gtk4, uuid and openssl development files, python3 and ImageMagick.
#
# Exits 0 when every check holds. The recordings of a check that failed are kept.

set -euo pipefail

layerkit="$(realpath "${1:?usage: check-layers.sh <LayerKit package directory> [check ...]}")"
shift
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

(cd "$layerkit" && swift build --product layer-compositor)
source ../Stdout/configure-env.sh
export OPENSWIFTUI_LAYERKIT_PATH="$layerkit"
swift build --disable-build-manifest-caching -Xcxx -include -Xcxx cstdint --product KitchenSink

# A tap on the bar at the bottom of a screen, a second and a half in. The finger lifts in
# frame 94, which layer-checks.py counts from.
go="1500:down:195,740;1560:up:195,740"

# A drag up the screen by 216 points in 0.4 s, lifted while still moving.
flick="1500:down:195,600"
for step in $(seq 1 12); do
    flick+=";$((1500 + step * 33)):move:195,$((600 - step * 18))"
done
flick+=";1904:up:195,384"

# name | screen | frames | one frame in how many is kept | touches | block: ms after a tap on the bar, for ms
checks=(
    "delayed-move|delayed-move|240|2|$go|150,1400"
    "moving-container|moving-container|240|2|$go|100,1500"
    "scale-rotation|scale-rotation|240|2|$go|100,1500"
    "repeating|repeating|300|2|$go|100,2500"
    "emptied-scroll|emptied-scroll|400|5|$flick;4500:down:195,740;4560:up:195,740;6000:down:195,400;6060:up:195,400|"
)

failed=0
for entry in "${checks[@]}"; do
    IFS='|' read -r name screen frames every touches stall <<< "$entry"
    if (($# > 0)) && [[ ! " $* " == *" $name "* ]]; then
        continue
    fi
    out="$(mktemp -d "${TMPDIR:-/tmp}/layer-check-$name.XXXXXX")"
    mkdir "$out/frames"
    echo "$name"

    LAYER_COMPOSITOR_SOCKET="$out/socket" "$layerkit/.build/debug/layer-compositor" \
        --fps 60 --frames "$frames" --stats "$out/stats.csv" --dump "$out/frames" --dump-every "$every" \
        --touches "$touches" > "$out/compositor.log" 2>&1 &
    compositor=$!
    for _ in $(seq 100); do
        [[ -S "$out/socket" ]] && break
        sleep 0.05
    done
    # The app ends by itself when the compositor has drawn its frames and gone.
    LAYER_COMPOSITOR_SOCKET="$out/socket" OPENSWIFTUI_HOST=layers KITCHEN_SINK_SCREEN="$screen" \
        KITCHEN_SINK_STALL="$stall" timeout $((frames / 60 + 20)) .build/debug/KitchenSink > "$out/app.log" 2>&1 &
    app=$!
    wait "$compositor" || true
    wait "$app" || true

    if python3 support/layer-checks.py "$name" "$out"; then
        rm -rf "$out"
    else
        failed=1
        echo "  kept: $out"
    fi
done
exit "$failed"
