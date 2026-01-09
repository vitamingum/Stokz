# AI Context - Stokz

## Dev Workflow (Build + Deploy + Logs)

**One command to build, install, and launch with live console:**
```bash
cd /Users/charlesburns/Stokz && \
xcodebuild -scheme Stokz -sdk iphoneos -configuration Debug build -quiet && \
xcrun devicectl device install app --device 00008150-001E08190A38401C \
  /Users/charlesburns/Library/Developer/Xcode/DerivedData/Stokz-bazhfupqpoomaxbihkzdvidadyrf/Build/Products/Debug-iphoneos/Stokz.app && \
xcrun devicectl device process launch --device 00008150-001E08190A38401C \
  --terminate-existing --console com.stokz.app 2>&1 | tee /tmp/stokz_log.txt
```

This kills any running app, launches fresh, and streams all `print()` output to terminal AND `/tmp/stokz_log.txt`.

**Check logs after user tests:**
```bash
cat /tmp/stokz_log.txt | tail -100
```

## Key IDs
- **Bundle**: `com.stokz.app`
- **Device**: `00008150-001E08190A38401C`
- **Team**: `MSW9JQ3H2Q`
- **App Store**: `6757373916`

## Fastlane (TestFlight)
```bash
fastlane beta  # Build + upload to TestFlight
```

## AI Stock Data Pipeline

Data: `Stokz/stock_data_bundle.json` (~1005 stocks, 788KB)

```bash
cd /Users/charlesburns/Stokz/pipeline
/Users/charlesburns/Stokz/.venv/bin/python run_russell3000_pipeline.py
# Options: --skip-wiki, --skip-facts
```
