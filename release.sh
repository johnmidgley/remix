#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check for Homebrew (needed to install dependencies)
if ! command -v brew >/dev/null 2>&1; then
    echo -e "${RED}✗ Homebrew not found${NC}"
    echo ""
    echo "Install it from: https://brew.sh"
    exit 1
fi

# Check for gh CLI
if ! command -v gh >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ GitHub CLI (gh) not found${NC}"
    read -p "Install it with Homebrew? [Y/n] " answer
    if [[ "$answer" =~ ^[Nn] ]]; then
        exit 1
    fi
    brew install gh
fi

# Check gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ Not authenticated with GitHub${NC}"
    echo "Opening GitHub login..."
    gh auth login
fi

# Get version from argument or prompt
VERSION="$1"
if [ -z "$VERSION" ]; then
    # Show recent tags for context
    LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
    echo "Latest tag: $LATEST_TAG"
    echo ""
    read -p "Version tag (e.g. v1.0.0): " VERSION
fi

if [ -z "$VERSION" ]; then
    echo -e "${RED}✗ No version specified${NC}"
    exit 1
fi

# Ensure version starts with 'v'
if [[ "$VERSION" != v* ]]; then
    VERSION="v$VERSION"
fi

# Check if tag already exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    echo -e "${RED}✗ Tag $VERSION already exists${NC}"
    exit 1
fi

# Check app bundle exists
APP_BUNDLE="$SCRIPT_DIR/Remix.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo -e "${YELLOW}App bundle not found. Building...${NC}"
    ./build-macos-app.sh
fi

# Detect architecture
ARCH=$(uname -m)

# Create zip
ZIP_NAME="Remix-macos-${ARCH}.zip"
echo ""
echo "Creating $ZIP_NAME..."
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_NAME"
ZIP_SIZE=$(du -h "$ZIP_NAME" | cut -f1)
echo -e "${GREEN}✓ Created $ZIP_NAME ($ZIP_SIZE)${NC}"

# Create release
echo ""
echo "Creating GitHub release $VERSION..."
gh release create "$VERSION" "$ZIP_NAME" \
    --title "Remix $VERSION" \
    --notes "$(cat <<EOF
## Remix $VERSION

macOS app with bundled Python and demucs. Fully standalone — no dependencies required.

### Installation
1. Download **$ZIP_NAME**
2. Unzip and drag **Remix.app** to your Applications folder
3. On first launch, right-click → Open (to bypass Gatekeeper)

### System Requirements
- macOS 13.0+
- Apple Silicon ($ARCH)
EOF
)"

echo ""
echo -e "${GREEN}✓ Release $VERSION created!${NC}"
RELEASE_URL=$(gh release view "$VERSION" --json url -q .url)
echo "  $RELEASE_URL"

# Clean up zip
rm -f "$ZIP_NAME"
