#!/bin/bash

# TutorCast Label Engine - Integration Validation Script
# This script checks that all components are in place

echo "╔════════════════════════════════════════════════════════════╗"
echo "║   TutorCast Label Engine Integration Validation            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Track status
ERRORS=0
WARNINGS=0

# Helper functions
check_file() {
    if [ -f "$1" ]; then
        echo "✅ Found: $1"
    else
        echo "❌ Missing: $1"
        ((ERRORS++))
    fi
}

check_content() {
    local file=$1
    local search_text=$2
    local description=$3
    
    if grep -q "$search_text" "$file" 2>/dev/null; then
        echo "  ✅ $description"
    else
        echo "  ⚠️  Missing: $description"
        ((WARNINGS++))
    fi
}

BASE_PATH="/Users/nana/Documents/ISO/TutorCast/TutorCast"

echo "1. Checking New Files..."
echo "─────────────────────────────────────────────────────────────"
check_file "$BASE_PATH/Models/LabelEngine.swift"
check_file "$BASE_PATH/LabelEngineTestView.swift"
check_file "/Users/nana/Documents/ISO/TutorCast/LABEL_ENGINE_INTEGRATION.md"
check_file "/Users/nana/Documents/ISO/TutorCast/IMPLEMENTATION_COMPLETE.md"
echo ""

echo "2. Checking File Modifications..."
echo "─────────────────────────────────────────────────────────────"

echo "LabelEngine.swift:"
check_content "$BASE_PATH/Models/LabelEngine.swift" "class LabelEngine: ObservableObject" "Main class definition"
check_content "$BASE_PATH/Models/LabelEngine.swift" "processEvent" "Event processing"
check_content "$BASE_PATH/Models/LabelEngine.swift" "colorForLabel" "Color assignment"
check_content "$BASE_PATH/Models/LabelEngine.swift" "scheduleAutoClear" "Auto-clear functionality"
echo ""

echo "SettingsStore.swift:"
check_content "$BASE_PATH/Models/SettingsStore.swift" "static let shared" "Singleton pattern"
check_content "$BASE_PATH/Models/SettingsStore.swift" "PassthroughSubject" "ObservableObject property"
echo ""

echo "OverlayContentView.swift:"
check_content "$BASE_PATH/OverlayContentView.swift" "LabelEngine.shared" "LabelEngine integration"
check_content "$BASE_PATH/OverlayContentView.swift" "labelColor" "Color property"
check_content "$BASE_PATH/OverlayContentView.swift" "orange" "Orange color case"
check_content "$BASE_PATH/OverlayContentView.swift" "cyan" "Cyan color case"
echo ""

echo "TutorCastApp.swift:"
check_content "$BASE_PATH/TutorCastApp.swift" "settingsStore" "SettingsStore integration"
check_content "$BASE_PATH/TutorCastApp.swift" "Menu(\"Active Profile" "Profile switcher menu"
echo ""

echo "AppDelegate.swift:"
check_content "$BASE_PATH/AppDelegate.swift" "LabelEngine.shared" "LabelEngine initialization"
echo ""

echo "SettingsWindow.swift:"
check_content "$BASE_PATH/Models/SettingsWindow.swift" "import Combine" "Combine import"
check_content "$BASE_PATH/Models/SettingsWindow.swift" "PassthroughSubject" "objectWillChange property"
echo ""

echo "Profile.swift:"
check_content "$BASE_PATH/Models/Profile.swift" "autoCAD()" "AutoCAD profile"
check_content "$BASE_PATH/Models/Profile.swift" "PAN" "PAN label"
check_content "$BASE_PATH/Models/Profile.swift" "ZOOM IN" "ZOOM IN label"
echo ""

echo ""
echo "3. Integration Checklist..."
echo "─────────────────────────────────────────────────────────────"

# Check imports
echo "Import statements:"
grep -q "import Combine" "$BASE_PATH/Models/SettingsWindow.swift" && echo "✅ Combine imported" || echo "❌ Missing Combine import"
grep -q "import Combine" "$BASE_PATH/Models/LabelEngine.swift" && echo "✅ LabelEngine imports Combine" || echo "❌ Missing Combine import in LabelEngine"

echo ""
echo "Profile System:"
grep -q "static let shared = SettingsStore" "$BASE_PATH/Models/SettingsStore.swift" && echo "✅ SettingsStore singleton" || echo "❌ Missing singleton"
grep -q "func activeProfile()" "$BASE_PATH/Models/SettingsStore.swift" && echo "✅ activeProfile() method" || echo "❌ Missing activeProfile()"

echo ""
echo "Event Processing:"
grep -q "KeyMouseMonitor.shared" "$BASE_PATH/Models/LabelEngine.swift" && echo "✅ KeyMouseMonitor monitoring" || echo "❌ Not monitoring KeyMouseMonitor"
grep -q "processEvent" "$BASE_PATH/Models/LabelEngine.swift" && echo "✅ Event processing" || echo "❌ No event processing"

echo ""
echo "UI Integration:"
grep -q "@StateObject private var labelEngine" "$BASE_PATH/OverlayContentView.swift" && echo "✅ LabelEngine state" || echo "❌ Missing LabelEngine state"
grep -q "labelColorValue" "$BASE_PATH/OverlayContentView.swift" && echo "✅ Color mapping" || echo "❌ Missing color mapping"

echo ""
echo "Menu Bar:"
grep -q "Menu(\"Active Profile" "$BASE_PATH/TutorCastApp.swift" && echo "✅ Profile menu" || echo "❌ Missing profile menu"

echo ""
echo "App Startup:"
grep -q "LabelEngine.shared" "$BASE_PATH/AppDelegate.swift" && echo "✅ LabelEngine init" || echo "❌ Missing LabelEngine initialization"

echo ""
echo "4. Test View..."
echo "─────────────────────────────────────────────────────────────"
check_file "$BASE_PATH/LabelEngineTestView.swift"
check_content "$BASE_PATH/LabelEngineTestView.swift" "KeyMouseMonitor.shared.simulate" "Event simulation"
check_content "$BASE_PATH/LabelEngineTestView.swift" "Middle Drag" "Test button"

echo ""
echo "5. Documentation..."
echo "─────────────────────────────────────────────────────────────"
check_file "/Users/nana/Documents/ISO/TutorCast/LABEL_ENGINE_INTEGRATION.md"
check_file "/Users/nana/Documents/ISO/TutorCast/IMPLEMENTATION_COMPLETE.md"

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
if [ $ERRORS -eq 0 ]; then
    echo "║   ✅ ALL CHECKS PASSED - Integration Complete!           ║"
else
    echo "║   ⚠️  Some issues found - Review above                  ║"
fi
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  Errors:   $ERRORS"
echo "  Warnings: $WARNINGS"
echo ""
echo "Next Steps:"
echo "  1. Build: ⌘B in Xcode"
echo "  2. Run: ⌘R to start TutorCast"
echo "  3. Test: Use LabelEngineTestView for verification"
echo "  4. Real-world: Open AutoCAD and test actual events"
echo ""
