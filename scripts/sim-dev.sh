#!/bin/bash
# Quick simulator development workflow
# Usage: ./scripts/sim-dev.sh [build|run|logs|all]

set -e
cd "$(dirname "$0")/.."

SIM_ID="A4AD70FC-EC4C-46DB-A589-6C7D69E4B731"
BUNDLE_ID="com.stokz.app"

case "${1:-all}" in
  build)
    echo "🔨 Building for simulator..."
    xcodebuild -scheme Stokz -destination "platform=iOS Simulator,id=$SIM_ID" -derivedDataPath build -quiet
    echo "✅ Build complete"
    ;;
  install)
    echo "📲 Installing..."
    xcrun simctl install "$SIM_ID" build/Build/Products/Debug-iphonesimulator/Stokz.app
    echo "✅ Installed"
    ;;
  run)
    echo "🚀 Launching app..."
    xcrun simctl launch "$SIM_ID" "$BUNDLE_ID"
    ;;
  logs)
    echo "📋 Streaming logs (Ctrl+C to stop)..."
    xcrun simctl spawn "$SIM_ID" log stream --predicate 'subsystem == "com.stokz.app" OR process == "Stokz"' --level debug
    ;;
  all)
    echo "🔄 Full cycle: build → install → run"
    $0 build
    $0 install
    # Start log streaming in background
    xcrun simctl spawn "$SIM_ID" log stream --predicate 'subsystem == "com.stokz.app"' --level info &
    LOG_PID=$!
    sleep 1
    $0 run
    echo ""
    echo "📋 Logs streaming... (Ctrl+C to stop)"
    wait $LOG_PID
    ;;
  *)
    echo "Usage: $0 [build|install|run|logs|all]"
    ;;
esac
