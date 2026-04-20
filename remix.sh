#!/bin/bash
set -e

# remix.sh — dev-iteration runner.
#
# Ensures the Remix.app bundle is up to date and launches the binary directly
# so NSLog/print output streams to the terminal (Ctrl-C kills it).
#
# First run (or when the bundle is missing Python / resources) delegates to
# build-macos-app.sh. Subsequent runs do an incremental Rust build and an
# optimized Swift recompile only when sources have changed. We match the
# release build's -O / -whole-module-optimization so runtime performance
# matches what you'd get from build-macos-app.sh — debug builds were causing
# visible UI spinners during interaction.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_BUNDLE="$SCRIPT_DIR/Remix.app"
BINARY="$APP_BUNDLE/Contents/MacOS/Remix"
PYTHON_BUNDLE="$APP_BUNDLE/Contents/Resources/python"

ARCH=$(uname -m)

SWIFT_SOURCES=(
    "macos-app/Remix/Sources/RemixApp.swift"
    "macos-app/Remix/Sources/AudioEngine.swift"
    "macos-app/Remix/Sources/ContentView.swift"
    "macos-app/Remix/Sources/LicensesView.swift"
    "macos-app/Remix/Sources/PreferencesView.swift"
)

HEADER_PATH="$SCRIPT_DIR/macos-app/Remix/Sources/remix.h"
LIB_PATH="$SCRIPT_DIR/target/release"
RUST_LIB="$LIB_PATH/libremix.a"

# Full build fallback — first run, wiped bundle, or missing Python.
if [ ! -x "$BINARY" ] || [ ! -d "$PYTHON_BUNDLE" ]; then
    echo "App bundle missing or incomplete — running full build..."
    "$SCRIPT_DIR/build-macos-app.sh"
    echo ""
    echo "Launching Remix..."
    exec "$BINARY"
fi

# Incremental Rust build. Quick no-op when nothing has changed.
echo "Checking Rust library..."
cargo build --release

# Decide whether Swift needs a recompile. Any source, the ObjC header, or a
# rebuilt Rust lib newer than the binary triggers a rebuild.
swift_rebuild=0
for src in "${SWIFT_SOURCES[@]}" "$HEADER_PATH" "$RUST_LIB"; do
    if [ -e "$src" ] && [ "$src" -nt "$BINARY" ]; then
        swift_rebuild=1
        break
    fi
done

if [ "$swift_rebuild" -eq 1 ]; then
    echo "Swift sources changed — recompiling (optimized)..."

    SDK=$(xcrun --show-sdk-path --sdk macosx)

    # Same static-linking trick as build-macos-app.sh.
    if [ -f "$LIB_PATH/libremix.dylib" ]; then
        mv "$LIB_PATH/libremix.dylib" "$LIB_PATH/libremix.dylib.bak"
    fi

    set +e
    swiftc \
        -O \
        -whole-module-optimization \
        -target ${ARCH}-apple-macosx13.0 \
        -sdk "$SDK" \
        -import-objc-header "$HEADER_PATH" \
        -L "$LIB_PATH" \
        -lremix \
        -framework AppKit \
        -framework SwiftUI \
        -framework AVFoundation \
        -framework CoreAudio \
        -framework Accelerate \
        "${SWIFT_SOURCES[@]}" \
        -o "$BINARY"
    build_rc=$?
    set -e

    if [ -f "$LIB_PATH/libremix.dylib.bak" ]; then
        mv "$LIB_PATH/libremix.dylib.bak" "$LIB_PATH/libremix.dylib"
    fi

    if [ $build_rc -ne 0 ]; then
        echo "Swift compilation failed" >&2
        exit 1
    fi

    # Re-sign in place — macOS rejects a modified binary otherwise.
    codesign --force --sign - "$APP_BUNDLE" >/dev/null
else
    echo "Binary up to date."
fi

echo ""
echo "Launching Remix..."
exec "$BINARY"
