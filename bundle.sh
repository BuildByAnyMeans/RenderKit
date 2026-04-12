#!/bin/bash
# ───────────────────────────────────────────────────────────────────────────────
# bundle.sh — Build RenderKit.app as a proper macOS application bundle
# ───────────────────────────────────────────────────────────────────────────────
# Creates a .app bundle with:
#   - Info.plist (so macOS treats it as a real app)
#   - The compiled binary
#   - An auto-generated app icon
#
# Usage:
#   ./bundle.sh              — Build and create RenderKit.app in ./build/
#   ./bundle.sh --install    — Also copy to /Applications
# ───────────────────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="RenderKit"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━ Building $APP_NAME.app ━━━${NC}"

# ── Step 1: Compile in release mode ──
echo -e "${YELLOW}Compiling (release mode)...${NC}"
swift build -c release 2>&1 | tail -3
echo -e "${GREEN}✓ Compiled${NC}"

# ── Step 2: Create .app bundle structure ──
echo -e "${YELLOW}Creating app bundle...${NC}"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES"

# Copy the binary
cp .build/release/RenderKit "$MACOS_DIR/RenderKit"

# ── Step 3: Write Info.plist ──
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>RenderKit</string>
    <key>CFBundleDisplayName</key>
    <string>RenderKit</string>
    <key>CFBundleIdentifier</key>
    <string>com.renderkit.app</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>RenderKit</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>HTML Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.html</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>CSS Stylesheet</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>css</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>JavaScript File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.netscape.javascript-source</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>JSON File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.json</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>React Component</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>jsx</string>
                <string>tsx</string>
                <string>ts</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Web Source File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>svg</string>
                <string>xml</string>
                <string>yaml</string>
                <string>yml</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Folder</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.folder</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
echo -e "${GREEN}✓ Info.plist written${NC}"

# ── Step 4: Convert custom icon PNG to .icns ──
echo -e "${YELLOW}Creating app icon...${NC}"

ICON_SRC="$SCRIPT_DIR/Icon/RenderKit Icon.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

if [ -f "$ICON_SRC" ]; then
    # Resize the source PNG into all required iconset sizes using sips
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"      > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"   > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"      > /dev/null 2>&1
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"   > /dev/null 2>&1
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"    > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"    > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"    > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1

    # Convert iconset → .icns
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES/AppIcon.icns" 2>/dev/null && \
        echo -e "${GREEN}✓ Custom app icon applied${NC}" || \
        echo -e "${YELLOW}⚠ iconutil failed — app will use default icon${NC}"
else
    echo -e "${YELLOW}⚠ Icon not found at: $ICON_SRC — using default icon${NC}"
fi

# Clean up temp iconset
rm -rf "$ICONSET_DIR"

# ── Step 5: Make executable ──
chmod +x "$MACOS_DIR/RenderKit"

echo ""
echo -e "${GREEN}━━━ Built: $APP_BUNDLE ━━━${NC}"
echo -e "  Size: $(du -sh "$APP_BUNDLE" | cut -f1)"

# ── Step 6: Optionally install to /Applications ──
if [ "${1:-}" = "--install" ]; then
    echo ""
    echo -e "${YELLOW}Installing to /Applications...${NC}"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    echo -e "${GREEN}✓ Installed to /Applications/$APP_NAME.app${NC}"
    echo -e "  You can now find it in Launchpad and Spotlight."
    echo ""
    # Clear the icon cache so the new icon shows up
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app" 2>/dev/null || true
else
    echo ""
    echo "To install to /Applications, run:"
    echo "  ./bundle.sh --install"
    echo ""
    echo "Or manually:"
    echo "  cp -R $APP_BUNDLE /Applications/"
fi
