#!/usr/bin/env bash
# Builds and runs the example in a GTK4 window on this machine.
# Needs Swift 6.3 and the gtk4, uuid and openssl development files.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

# Compute as the graph engine, and the toolchain's libraries on the link and runtime paths.
source ../Stdout/configure-env.sh

# Compute 0.6.4 uses std::uint64_t without <cstdint>; libstdc++ 16 no longer includes it
# transitively.
exec swift run -Xcxx -include -Xcxx cstdint ExampleApp "$@"
