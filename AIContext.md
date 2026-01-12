# AI Context - Stokz

## Project Layout (~30 Swift files, ~8,000 LOC)

```
Stokz/
├── StokzApp.swift          # Entry point
├── ContentView.swift       # Tab container
├── AppState.swift          # Global state coordinator
├── Models/
│   └── Models.swift        # User, Portfolio, Stock, LeaderboardEntry
├── Services/
│   ├── GoogleSheetsService # Users + portfolios from Sheets
│   ├── StockPriceService   # Live prices from Finnhub
│   ├── StockDataService    # Company info from JSON bundle
│   ├── PortfolioManager    # Buy/sell logic
│   ├── AuthenticationService
│   ├── GeminiService       # AI taglines + chat via Gemini API
│   ├── StockScreenerService # AI batch stock screening (map-reduce)
│   ├── Secrets.swift       # API keys (GITIGNORED)
│   └── Logger
├── Views/
│   ├── PortfolioView       # User's holdings + AI screener chat
│   ├── StockScreenerChatView # Chat input + results for AI screening
│   ├── LeaderboardView     # Ranked players + AI taglines
│   ├── UsersView           # All players
│   ├── StocksView          # All stocks union
│   ├── SettingsView        # Debug console
│   ├── AddStockView        # Search + add stocks
│   ├── StockDiscoveryView  # AI company info
│   └── (5 more views)
├── Components/
│   ├── StockRowView
│   └── UserRowView
├── Extensions.swift        # Currency/date formatters
└── stock_data_bundle.json  # 1005 companies (788KB)
```

## Xcode Project Edits (Adding New Swift Files)

To add a new Swift file to the Xcode project via code, edit `Stokz.xcodeproj/project.pbxproj`:

1. **PBXBuildFile section** - Add build reference:
   ```
   A1000032 /* MyFile.swift in Sources */ = {isa = PBXBuildFile; fileRef = A2000032 /* MyFile.swift */; };
   ```

2. **PBXFileReference section** - Add file reference:
   ```
   A2000032 /* MyFile.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MyFile.swift; sourceTree = "<group>"; };
   ```

3. **PBXGroup section** - Add to appropriate group (Services/Views/etc):
   ```
   A2000032 /* MyFile.swift */,
   ```

4. **PBXSourcesBuildPhase section** - Add to Sources:
   ```
   A1000032 /* MyFile.swift in Sources */,
   ```

Use incrementing IDs (A1000032, A2000032, etc.) - check existing highest ID first.

## Gemini API Integration
- **Service**: `GeminiService.swift` - taglines + general chat
- **API Key**: Store in `Secrets.swift` (gitignored) - get from https://aistudio.google.com/app/apikey
- **Model**: `gemini-2.0-flash`
- **Usage**: LeaderboardView taglines, StockScreenerService batch evaluation
- **Billing**: Must link Google Cloud billing for quota (free tier: 1500/day)

## AI Stock Screener (Map-Reduce Pattern)
- **Service**: `StockScreenerService.swift`
- **Flow**: User prompt → criteria generation → batch evaluation (100 stocks/call) → final picks
- **UI**: `StockScreenerChatView.swift` embedded in PortfolioView
- **Cost**: ~10-30 API calls per full screen (~$0.002 with Gemini Flash)

## Dev Workflow (Build + Deploy + Logs)

**One command to build, install, and launch with live console:**
```bash
cd /Users/charlesburns/Stokz && \
xcodebuild -scheme Stokz -sdk iphoneos -configuration Debug build -quiet && \
xcrun devicectl device install app --device C1B7A796-4BCA-5296-A9BB-253A01A873F9 \
  /Users/charlesburns/Library/Developer/Xcode/DerivedData/Stokz-bazhfupqpoomaxbihkzdvidadyrf/Build/Products/Debug-iphoneos/Stokz.app && \
xcrun devicectl device process launch --device C1B7A796-4BCA-5296-A9BB-253A01A873F9 \
  --terminate-existing com.stokz.app
```

**Check logs:** `cat /tmp/stokz_log.txt | tail -100`

## Key IDs
- **Bundle**: `com.stokz.app`
- **Device**: `C1B7A796-4BCA-5296-A9BB-253A01A873F9` (iPhone 17 Pro)
- **Team**: `MSW9JQ3H2Q`
- **App Store**: `6757373916`

## Fastlane (TestFlight)
```bash
fastlane beta  # Build + upload to TestFlight
```

## AI Stock Data Pipeline
```bash
cd /Users/charlesburns/Stokz/pipeline
.venv/bin/python run_russell3000_pipeline.py  # Options: --skip-wiki, --skip-facts
```
