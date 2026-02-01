#!/bin/bash
set -e

# Build script for Remix macOS app
# This script compiles the Rust library and builds the Swift macOS app with bundled Python
#
# Build Requirements (your machine only):
#   - Rust (for building the Rust library)
#   - Xcode Command Line Tools (for Swift compilation)
#   - Python 3.8+ (for creating the Python bundle)
#
# User Requirements (zero!):
#   - Nothing! Python and demucs are bundled in the app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Building Remix for macOS"
echo "(with bundled Python - fully standalone!)"
echo "=========================================="

# Detect architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

# Python check (will be bundled automatically during build)
echo ""
echo "Python will be bundled automatically."
echo "The app will be fully standalone with no user dependencies."
echo ""

# Build Rust library and binaries
echo ""
echo "Step 1: Building Rust library and tools..."
cargo build --release

# Check if library was built
if [ ! -f "target/release/libremix.a" ]; then
    echo "Error: Rust library not found at target/release/libremix.a"
    exit 1
fi
echo "Rust library built successfully"

# Create app bundle structure
echo ""
echo "Step 2: Creating app bundle..."
APP_NAME="Remix"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Remix</string>
    <key>CFBundleIdentifier</key>
    <string>com.remix.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Remix</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>Remix</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Audio File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>com.microsoft.waveform-audio</string>
                <string>public.mp3</string>
            </array>
        </dict>
    </array>
    <key>NSMicrophoneUsageDescription</key>
    <string>Remix needs microphone access for audio processing.</string>
</dict>
</plist>
PLIST

# Compile Swift code
echo ""
echo "Step 3: Compiling Swift application..."

SWIFT_SOURCES=(
    "macos-app/Remix/Sources/RemixApp.swift"
    "macos-app/Remix/Sources/AudioEngine.swift"
    "macos-app/Remix/Sources/ContentView.swift"
    "macos-app/Remix/Sources/LicensesView.swift"
)

HEADER_PATH="$SCRIPT_DIR/macos-app/Remix/Sources/remix.h"
LIB_PATH="$SCRIPT_DIR/target/release"

# Remove the dylib temporarily to force static linking
if [ -f "$LIB_PATH/libremix.dylib" ]; then
    mv "$LIB_PATH/libremix.dylib" "$LIB_PATH/libremix.dylib.bak"
fi

# Compile with swiftc (force static linking by removing dylib)
swiftc \
    -O \
    -whole-module-optimization \
    -target ${ARCH}-apple-macosx13.0 \
    -sdk $(xcrun --show-sdk-path --sdk macosx) \
    -import-objc-header "$HEADER_PATH" \
    -L "$LIB_PATH" \
    -lremix \
    -framework AppKit \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework Accelerate \
    "${SWIFT_SOURCES[@]}" \
    -o "$MACOS_DIR/Remix"

BUILD_RESULT=$?

# Restore the dylib
if [ -f "$LIB_PATH/libremix.dylib.bak" ]; then
    mv "$LIB_PATH/libremix.dylib.bak" "$LIB_PATH/libremix.dylib"
fi

if [ $BUILD_RESULT -ne 0 ]; then
    echo "Error: Swift compilation failed"
    exit 1
fi

echo "Swift application compiled successfully"

# Generate app icon
echo ""
echo "Step 4: Generating app icon..."
ICONSET_DIR="$SCRIPT_DIR/scripts/Remix.iconset"
ICNS_PATH="$SCRIPT_DIR/scripts/Remix.icns"
SOURCE_PNG="$SCRIPT_DIR/scripts/Remix.png"

if [ -f "$SOURCE_PNG" ]; then
    echo "Using Remix.png as icon source..."
    mkdir -p "$ICONSET_DIR"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$SOURCE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
else
    echo "No Remix.png found, generating icon..."
    "$SCRIPT_DIR/target/release/generate_icon"
fi
cp "$ICNS_PATH" "$RESOURCES_DIR/"

# Copy license and attribution files
echo "Copying license files..."
cp "$SCRIPT_DIR/LICENSE" "$RESOURCES_DIR/"
cp "$SCRIPT_DIR/THIRD_PARTY_LICENSES.md" "$RESOURCES_DIR/"
cp "$SCRIPT_DIR/ABOUT.txt" "$RESOURCES_DIR/"

# Bundle Python with the app
echo ""
echo "Step 5: Bundling Python..."
"$SCRIPT_DIR/scripts/bundle_python.sh" "$APP_BUNDLE"

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to bundle Python${NC}"
    exit 1
fi

# Sign the app (ad-hoc for local development)
echo ""
echo "Step 6: Signing application..."
codesign --force --deep --sign - "$APP_BUNDLE"

# Calculate final app size
APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "App size: $APP_SIZE"

echo ""
echo "=========================================="
echo "Build complete!"
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run: open \"$APP_BUNDLE\""
echo "=========================================="
