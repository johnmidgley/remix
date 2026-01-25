#!/bin/bash
set -e

# Build script for Remix macOS app
# This script compiles the Rust library and builds the Swift macOS app
#
# Requirements:
#   - Rust (for building)
#   - Xcode Command Line Tools (for Swift compilation)
#   - Python 3 with demucs package (pip install demucs)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "Building Remix for macOS"
echo "(uses Python demucs for stem separation)"
echo "=========================================="

# Detect architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

# Build Rust library and binaries
echo ""
echo "Step 1: Building Rust library and tools..."
cargo build --release

# Check if library was built
if [ ! -f "target/release/libmusic_tool.a" ]; then
    echo "Error: Rust library not found at target/release/libmusic_tool.a"
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
)

HEADER_PATH="$SCRIPT_DIR/macos-app/Remix/Sources/music_tool.h"
LIB_PATH="$SCRIPT_DIR/target/release"

# Remove the dylib temporarily to force static linking
if [ -f "$LIB_PATH/libmusic_tool.dylib" ]; then
    mv "$LIB_PATH/libmusic_tool.dylib" "$LIB_PATH/libmusic_tool.dylib.bak"
fi

# Compile with swiftc (force static linking by removing dylib)
swiftc \
    -O \
    -whole-module-optimization \
    -target ${ARCH}-apple-macosx13.0 \
    -sdk $(xcrun --show-sdk-path --sdk macosx) \
    -import-objc-header "$HEADER_PATH" \
    -L "$LIB_PATH" \
    -lmusic_tool \
    -framework AppKit \
    -framework SwiftUI \
    -framework AVFoundation \
    -framework CoreAudio \
    -framework Accelerate \
    "${SWIFT_SOURCES[@]}" \
    -o "$MACOS_DIR/Remix"

BUILD_RESULT=$?

# Restore the dylib
if [ -f "$LIB_PATH/libmusic_tool.dylib.bak" ]; then
    mv "$LIB_PATH/libmusic_tool.dylib.bak" "$LIB_PATH/libmusic_tool.dylib"
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

# Note: ONNX models no longer needed - app uses Python demucs subprocess

# Sign the app (ad-hoc for local development)
echo ""
echo "Step 5: Signing application..."
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
