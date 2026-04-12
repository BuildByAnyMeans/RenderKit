#!/bin/bash
# ───────────────────────────────────────────────────────────────────────────────
# RenderKit — Build & Run Helper Script
# ───────────────────────────────────────────────────────────────────────────────
# Usage:
#   ./setup.sh          — Build and run the app
#   ./setup.sh build    — Build only (no run)
#   ./setup.sh clean    — Clean build artifacts
#   ./setup.sh xcode    — Generate Xcode project (requires xcodegen)
# ───────────────────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  RenderKit — Native macOS Front-End Previewer${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_requirements() {
    echo -e "${YELLOW}Checking requirements...${NC}"

    # Check for Xcode/Swift
    if ! command -v swift &> /dev/null; then
        echo -e "${RED}Error: Swift is not installed.${NC}"
        echo "Install Xcode from the Mac App Store, or run:"
        echo "  xcode-select --install"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Swift $(swift --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?')"

    # Check for Node.js (optional, for JSX/dev server features)
    if command -v node &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} Node.js $(node --version)"
    else
        echo -e "  ${YELLOW}⚠${NC} Node.js not found (optional — needed for JSX preview and dev servers)"
    fi

    # Check for npm (optional)
    if command -v npm &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} npm $(npm --version)"
    else
        echo -e "  ${YELLOW}⚠${NC} npm not found (optional — needed for JSX preview and dev servers)"
    fi

    echo ""
}

build() {
    echo -e "${YELLOW}Building RenderKit...${NC}"
    swift build -c release 2>&1 | tail -5
    echo -e "${GREEN}Build successful!${NC}"
    echo ""
}

run() {
    echo -e "${YELLOW}Launching RenderKit...${NC}"
    echo -e "${GREEN}The app window should appear momentarily.${NC}"
    echo -e "Press Ctrl+C to quit."
    echo ""
    swift run -c release
}

clean() {
    echo -e "${YELLOW}Cleaning build artifacts...${NC}"
    swift package clean
    rm -rf .build
    echo -e "${GREEN}Clean complete.${NC}"
}

generate_xcode() {
    if ! command -v xcodegen &> /dev/null; then
        echo -e "${YELLOW}XcodeGen not found. Installing via Homebrew...${NC}"
        brew install xcodegen
    fi
    echo -e "${YELLOW}Generating Xcode project...${NC}"
    xcodegen generate
    echo -e "${GREEN}Done! Open RenderKit.xcodeproj in Xcode.${NC}"
    open RenderKit.xcodeproj
}

# ── Main ──

print_header

case "${1:-}" in
    build)
        check_requirements
        build
        ;;
    clean)
        clean
        ;;
    xcode)
        generate_xcode
        ;;
    *)
        check_requirements
        build
        run
        ;;
esac
