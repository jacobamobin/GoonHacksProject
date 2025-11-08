#!/bin/bash
# Project Verification Script
# Run this to verify all files are in place

echo "🔍 Verifying Sperm Racing Project..."
echo ""

PROJECT_DIR="/Users/jacobmobin/Documents/GoonHacksProject"
GAME_DIR="$PROJECT_DIR/GoonHacksGame/GoonHacksGame/GoonHacksGame"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

all_good=true

# Function to check file
check_file() {
    local file=$1
    local description=$2

    if [ -f "$file" ]; then
        local size=$(ls -lh "$file" | awk '{print $5}')
        echo -e "${GREEN}✅${NC} $description ($size)"
    else
        echo -e "${RED}❌${NC} $description - MISSING!"
        all_good=false
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 Swift Source Files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "$GAME_DIR/AppDelegate.swift" "AppDelegate.swift"
check_file "$GAME_DIR/ViewController.swift" "ViewController.swift"
check_file "$GAME_DIR/GameCoordinator.swift" "GameCoordinator.swift"
check_file "$GAME_DIR/Tracklet.swift" "Tracklet.swift"
check_file "$GAME_DIR/GameModels.swift" "GameModels.swift"
check_file "$GAME_DIR/LobbyScene.swift" "LobbyScene.swift"
check_file "$GAME_DIR/RaceGameScene.swift" "RaceGameScene.swift"
check_file "$GAME_DIR/MultipeerManager.swift" "MultipeerManager.swift"
check_file "$GAME_DIR/MotionController.swift" "MotionController.swift"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Data Files"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "$GAME_DIR/tracklets_for_game.json" "Tracklet JSON (game bundle)"
check_file "$PROJECT_DIR/visem-tracking-main/tracklets_for_game.json" "Tracklet JSON (source)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📖 Documentation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "$PROJECT_DIR/BUILD_AND_TEST_GUIDE.md" "Build & Test Guide"
check_file "$PROJECT_DIR/IMPLEMENTATION_GUIDE.md" "Implementation Guide"
check_file "$PROJECT_DIR/SPERM_RACING_README.md" "Game README"
check_file "$PROJECT_DIR/PROJECT_COMPLETE.md" "Project Summary"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Xcode Project"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_file "$PROJECT_DIR/GoonHacksGame/GoonHacksGame.xcodeproj/project.pbxproj" "Xcode Project File"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 Statistics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

swift_files=$(find "$GAME_DIR" -name "*.swift" -type f 2>/dev/null | wc -l | tr -d ' ')
total_lines=$(find "$GAME_DIR" -name "*.swift" -type f -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}')

echo -e "Swift files: ${YELLOW}$swift_files${NC}"
echo -e "Total lines: ${YELLOW}$total_lines${NC}"

# Check tracklet data
if [ -f "$GAME_DIR/tracklets_for_game.json" ]; then
    tracklet_count=$(grep -o '"id":' "$GAME_DIR/tracklets_for_game.json" | wc -l | tr -d ' ')
    echo -e "Tracklets loaded: ${YELLOW}$tracklet_count${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "1. Open Xcode:"
echo -e "   ${YELLOW}open $PROJECT_DIR/GoonHacksGame/GoonHacksGame.xcodeproj${NC}"
echo ""
echo "2. Add Swift files to project (if needed):"
echo "   - Right-click 'GoonHacksGame' folder in Xcode"
echo "   - Select 'Add Files to GoonHacksGame...'"
echo "   - Select all .swift files"
echo "   - Check 'Copy items if needed'"
echo "   - Click 'Add'"
echo ""
echo "3. Add tracklets JSON to Bundle Resources:"
echo "   - Select project → GoonHacksGame target"
echo "   - Build Phases → Copy Bundle Resources"
echo "   - Click '+' → Add tracklets_for_game.json"
echo ""
echo "4. Build and Run:"
echo "   - Press ⌘B to build"
echo "   - Press ⌘R to run"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$all_good" = true ]; then
    echo -e "${GREEN}✅ All files verified! Project is ready to build.${NC}"
    exit 0
else
    echo -e "${RED}❌ Some files are missing. Check the errors above.${NC}"
    exit 1
fi
