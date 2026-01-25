#!/bin/bash
set -e

# Build script for Remix macOS app
# This script compiles the Rust library and builds the Swift macOS app
#
# Options:
#   --no-models    Skip bundling Demucs models (smaller app, but requires
#                  ~4GB download on first use)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
# Models are bundled by default, use --no-models to skip
BUNDLE_MODELS=true
for arg in "$@"; do
    case $arg in
        --no-models)
            BUNDLE_MODELS=false
            shift
            ;;
    esac
done

echo "=========================================="
echo "Building Remix for macOS"
if [ "$BUNDLE_MODELS" = true ]; then
    echo "(with bundled Demucs models)"
else
    echo "(without models - will download on first use)"
fi
echo "=========================================="

# Detect architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

# Build Rust library
echo ""
echo "Step 1: Building Rust library..."
cargo build --release --lib

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

# Copy resources (Python + app icon)
echo ""
echo "Step 4: Copying resources..."
cp "$SCRIPT_DIR/scripts/demucs_separate.py" "$RESOURCES_DIR/"
python3 "$SCRIPT_DIR/scripts/generate_app_icon.py"
cp "$SCRIPT_DIR/scripts/Remix.icns" "$RESOURCES_DIR/"

# Download and bundle models if requested
if [ "$BUNDLE_MODELS" = true ]; then
    echo ""
    echo "Step 4b: Downloading and bundling Demucs models..."
    MODELS_DIR="$RESOURCES_DIR/models"
    mkdir -p "$MODELS_DIR"
    
    # Run the download script
    python3 "$SCRIPT_DIR/scripts/download_models.py" -o "$MODELS_DIR" -m htdemucs_6s
    
    if [ $? -eq 0 ]; then
        echo "Models bundled successfully"
        # Show size
        MODELS_SIZE=$(du -sh "$MODELS_DIR" | cut -f1)
        echo "Models directory size: $MODELS_SIZE"
    else
        echo "Warning: Failed to download models, app will download on first use"
    fi
fi

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
