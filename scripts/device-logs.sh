#!/bin/bash
# Stream iOS device logs using native Apple devicectl
# No third-party dependencies required!

DEVICE_ID="C1B7A796-4BCA-5296-A9BB-253A01A873F9"
BUNDLE_ID="com.stokz.app"

echo "📱 iOS Device Log Streamer (Native)"
echo "==================================="
echo ""
echo "Device: $DEVICE_ID"
echo "Bundle: $BUNDLE_ID"
echo ""

# Launch app with console streaming
# --terminate-existing kills any running instance first
# --console streams stdout/stderr to terminal
xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --console \
    --terminate-existing \
    "$BUNDLE_ID"
