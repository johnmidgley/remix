#!/bin/bash
set -e

# Build script for Remix macOS app
# This script compiles the Rust library and builds the Swift macOS app
#
# Requirements:
#   - Rust (for building)
#   - Xcode Command Line Tools (for Swift compilation)
#   - Python 3 with demucs, librosa, and soundfile packages

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
echo "(uses Python demucs for stem separation)"
echo "=========================================="

# Detect architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

# Check Python dependencies
echo ""
echo "Checking Python dependencies..."
echo "=========================================="

# Find Python 3
PYTHON_CMD=""
for cmd in python3 python /usr/bin/python3 /usr/local/bin/python3; do
    if command -v "$cmd" >/dev/null 2>&1; then
        if "$cmd" -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" 2>/dev/null; then
            PYTHON_CMD="$cmd"
            break
        fi
    fi
done

if [ -z "$PYTHON_CMD" ]; then
    echo -e "${RED}✗ Python 3.8+ not found${NC}"
    echo "  Please install Python 3: https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$("$PYTHON_CMD" --version 2>&1 | cut -d' ' -f2)
echo -e "${GREEN}✓ Python $PYTHON_VERSION found${NC} ($PYTHON_CMD)"

# Find pip
PIP_CMD=""
for cmd in pip3 pip "$PYTHON_CMD -m pip"; do
    if eval "$cmd --version" >/dev/null 2>&1; then
        PIP_CMD="$cmd"
        break
    fi
done

if [ -z "$PIP_CMD" ]; then
    echo -e "${RED}✗ pip not found${NC}"
    echo "  Please install pip: https://pip.pypa.io/en/stable/installation/"
    exit 1
fi

echo -e "${GREEN}✓ pip found${NC}"

# Check required packages
REQUIRED_PACKAGES=("demucs")
MISSING_PACKAGES=()

for package in "${REQUIRED_PACKAGES[@]}"; do
    if "$PYTHON_CMD" -c "import $package" 2>/dev/null; then
        PACKAGE_VERSION=$("$PYTHON_CMD" -c "import $package; print(getattr($package, '__version__', 'unknown'))" 2>/dev/null)
        echo -e "${GREEN}✓ $package${NC} ($PACKAGE_VERSION)"
    else
        echo -e "${YELLOW}✗ $package not installed${NC}"
        MISSING_PACKAGES+=("$package")
    fi
done

# Install missing packages if any
if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Missing required Python packages:${NC} ${MISSING_PACKAGES[*]}"
    echo ""
    read -p "Would you like to install them now? (y/n) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Installing Python packages...${NC}"
        $PIP_CMD install "${MISSING_PACKAGES[@]}"
        
        # Verify installation
        echo ""
        echo "Verifying installation..."
        ALL_INSTALLED=true
        for package in "${MISSING_PACKAGES[@]}"; do
            if "$PYTHON_CMD" -c "import $package" 2>/dev/null; then
                echo -e "${GREEN}✓ $package installed successfully${NC}"
            else
                echo -e "${RED}✗ Failed to install $package${NC}"
                ALL_INSTALLED=false
            fi
        done
        
        if [ "$ALL_INSTALLED" = false ]; then
            echo ""
            echo -e "${RED}Some packages failed to install. Please install manually:${NC}"
            echo "  $PIP_CMD install ${MISSING_PACKAGES[*]}"
            exit 1
        fi
    else
        echo ""
        echo -e "${RED}Build cancelled.${NC} Please install required packages first:"
        echo "  $PIP_CMD install ${MISSING_PACKAGES[*]}"
        echo ""
        echo "Then run this script again."
        exit 1
    fi
fi

echo ""
echo -e "${GREEN}All Python dependencies satisfied!${NC}"
echo "=========================================="

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
