#!/bin/bash
set -e

# Bundle Python with the Remix app
# This creates a minimal, standalone Python distribution inside the .app bundle

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "Bundling Python for Remix"
echo "=========================================="

# Check if we're building the app
if [ -z "$1" ]; then
    echo "Usage: $0 <app-bundle-path>"
    echo "Example: $0 Remix.app"
    exit 1
fi

APP_BUNDLE="$1"
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${RED}Error: App bundle not found: $APP_BUNDLE${NC}"
    exit 1
fi

PYTHON_DIR="$APP_BUNDLE/Contents/Resources/python"
BIN_DIR="$PYTHON_DIR/bin"
LIB_DIR="$PYTHON_DIR/lib"

echo ""
echo "Creating minimal Python distribution..."
echo "=========================================="

# Find Python 3 - prefer Homebrew or python.org builds over system Python
PYTHON_CMD=""

# Try Homebrew first (more relocatable)
for cmd in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/local/opt/python@*/bin/python3; do
    if [ -f "$cmd" ]; then
        if "$cmd" -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" 2>/dev/null; then
            PYTHON_CMD="$cmd"
            echo -e "${GREEN}✓ Found Homebrew Python${NC}"
            break
        fi
    fi
done

# Try python.org installation
if [ -z "$PYTHON_CMD" ]; then
    for cmd in /Library/Frameworks/Python.framework/Versions/*/bin/python3; do
        if [ -f "$cmd" ]; then
            if "$cmd" -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" 2>/dev/null; then
                PYTHON_CMD="$cmd"
                echo -e "${GREEN}✓ Found python.org Python${NC}"
                break
            fi
        fi
    done
fi

# Fall back to any python3
if [ -z "$PYTHON_CMD" ]; then
    for cmd in python3 python; do
        if command -v "$cmd" >/dev/null 2>&1; then
            if "$cmd" -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" 2>/dev/null; then
                PYTHON_CMD="$cmd"
                echo -e "${YELLOW}⚠ Using system Python (may have framework dependencies)${NC}"
                break
            fi
        fi
    done
fi

if [ -z "$PYTHON_CMD" ]; then
    echo -e "${RED}✗ Python 3.8+ not found${NC}"
    echo ""
    echo "Please install Python 3.8+ from:"
    echo "  - Homebrew: brew install python3"
    echo "  - python.org: https://www.python.org/downloads/"
    exit 1
fi

PYTHON_VERSION=$("$PYTHON_CMD" --version 2>&1 | cut -d' ' -f2)
echo -e "${GREEN}✓ Found Python $PYTHON_VERSION${NC}"
PYTHON_PATH=$("$PYTHON_CMD" -c "import sys; print(sys.executable)")
echo "  Path: $PYTHON_PATH"

# Create virtual environment for bundling
echo ""
echo "Creating isolated environment..."
VENV_DIR="$PROJECT_DIR/.python_bundle"
rm -rf "$VENV_DIR"

# Use --copies to create standalone Python binaries (not symlinks)
"$PYTHON_CMD" -m venv --copies "$VENV_DIR"

# Activate venv
source "$VENV_DIR/bin/activate"

# Install only required packages
echo ""
echo "Installing dependencies (this may take a few minutes)..."
pip install --quiet --upgrade pip
pip install --quiet demucs

echo -e "${GREEN}✓ Dependencies installed${NC}"

# Get Python version
PYTHON_VERSION_SHORT=$("$VENV_DIR/bin/python3" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

# Create bundle directory structure
echo ""
echo "Creating bundle structure..."
rm -rf "$PYTHON_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$LIB_DIR/python${PYTHON_VERSION_SHORT}"

# Copy the entire venv (it's already self-contained)
echo "  Copying Python environment..."
cp -R "$VENV_DIR/bin/"* "$BIN_DIR/" 2>/dev/null || true
cp -R "$VENV_DIR/lib/python${PYTHON_VERSION_SHORT}/"* "$LIB_DIR/python${PYTHON_VERSION_SHORT}/" 2>/dev/null || true

# Also copy any dylibs from the lib directory root
if [ -d "$VENV_DIR/lib" ]; then
    cp "$VENV_DIR/lib/"*.dylib "$LIB_DIR/" 2>/dev/null || true
fi

# Create symlinks in bin
cd "$BIN_DIR"
if [ ! -e "python" ]; then
    ln -s python3 python
fi
cd - > /dev/null

echo -e "${GREEN}✓ Python environment copied${NC}"

# Clean up unnecessary files to reduce size
echo ""
echo "Pruning unnecessary files..."

# Remove caches and test files
find "$PYTHON_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.pyo" -delete 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.dist-info" -delete 2>/dev/null || true

# Remove docs and examples
find "$PYTHON_DIR" -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true
find "$PYTHON_DIR" -type d -name "doc" -exec rm -rf {} + 2>/dev/null || true

# Remove build artifacts
find "$PYTHON_DIR" -type f -name "*.c" -delete 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.cpp" -delete 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.h" -delete 2>/dev/null || true
find "$PYTHON_DIR" -type f -name "*.pyx" -delete 2>/dev/null || true

echo -e "${GREEN}✓ Unnecessary files removed${NC}"

# Create Python wrapper script
echo ""
echo "Creating Python wrapper..."
cat > "$BIN_DIR/python-wrapper.sh" << 'EOF'
#!/bin/bash
# Wrapper script to use bundled Python with correct paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$(dirname "$PYTHON_DIR")"
CONTENTS_DIR="$(dirname "$RESOURCES_DIR")"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

# Set Python paths
export PYTHONHOME="$PYTHON_DIR"

# Find Python version
PYTHON_VERSION=$(ls "$PYTHON_DIR/lib" | grep "^python3\.[0-9]" | head -1 | sed 's/python//')
export PYTHONPATH="$PYTHON_DIR/lib/python$PYTHON_VERSION/site-packages:$PYTHON_DIR/lib/python$PYTHON_VERSION"

# Set library paths for any dylibs
export DYLD_LIBRARY_PATH="$PYTHON_DIR/lib:$FRAMEWORKS_DIR:$DYLD_LIBRARY_PATH"
export DYLD_FRAMEWORK_PATH="$FRAMEWORKS_DIR:$DYLD_FRAMEWORK_PATH"

# Disable .pyc files to avoid permission issues
export PYTHONDONTWRITEBYTECODE=1

exec "$SCRIPT_DIR/python3" "$@"
EOF

chmod +x "$BIN_DIR/python-wrapper.sh"

# Deactivate venv
deactivate

# Test if bundled Python works
echo ""
echo "Testing bundled Python..."
if ! "$BIN_DIR/python-wrapper.sh" -c "import sys; print('Python works!')" > /dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Python needs framework dependencies${NC}"
    
    # Check if Python is framework-based
    PYTHON_FRAMEWORK=$(otool -L "$BIN_DIR/python3" 2>/dev/null | grep "Python3.framework" || true)
    
    if [ -n "$PYTHON_FRAMEWORK" ]; then
        echo "  Copying Python.framework..."
        FRAMEWORKS_DIR="$(dirname "$(dirname "$PYTHON_DIR")")/Frameworks"
        mkdir -p "$FRAMEWORKS_DIR"
        
        # Find the framework path
        FRAMEWORK_PATH=$("$VENV_DIR/bin/python3" -c "import sys, os; print(os.path.dirname(os.path.dirname(sys.executable)))" 2>/dev/null || echo "")
        
        if [ -d "$FRAMEWORK_PATH" ] && [[ "$FRAMEWORK_PATH" == *"Python.framework"* ]]; then
            # Copy minimal framework
            cp -R "$FRAMEWORK_PATH" "$FRAMEWORKS_DIR/" 2>/dev/null || true
            echo -e "${GREEN}✓ Framework copied${NC}"
        else
            echo -e "${YELLOW}⚠ Could not locate Python.framework${NC}"
            echo "  Bundled Python may not work standalone."
            echo "  Consider installing Python from Homebrew: brew install python3"
        fi
    fi
else
    echo -e "${GREEN}✓ Bundled Python works!${NC}"
fi

# Clean up temporary venv
rm -rf "$VENV_DIR"

# Calculate size
BUNDLE_SIZE=$(du -sh "$PYTHON_DIR" | cut -f1)

echo ""
echo "=========================================="
echo -e "${GREEN}✓ Python bundled successfully!${NC}"
echo "=========================================="
echo "  Location: $PYTHON_DIR"
echo "  Size: $BUNDLE_SIZE"
echo "  Python version: $PYTHON_VERSION"
echo ""
echo "The app now includes:"
echo "  - Python $PYTHON_VERSION"
echo "  - demucs package"
echo "  - All required dependencies"
echo ""
echo "Users don't need to install anything!"
echo "=========================================="
