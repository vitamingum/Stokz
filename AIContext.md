# AI Context - Stokz

## Project Layout (25 Swift files, ~6,800 LOC)

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
│   └── Logger
├── Views/
│   ├── PortfolioView       # User's holdings
│   ├── LeaderboardView     # Ranked players
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

**Check logs:** `cat /tmp/stokz_log.txt | tail -100`

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
```bash
cd /Users/charlesburns/Stokz/pipeline
.venv/bin/python run_russell3000_pipeline.py  # Options: --skip-wiki, --skip-facts
```
