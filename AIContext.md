# AI Context - Stokz

## Project Layout (26 Swift files, ~7,000 LOC)

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
│   ├── GeminiService       # AI taglines via Gemini API
│   ├── Secrets.swift       # API keys (GITIGNORED)
│   └── Logger
├── Views/
│   ├── PortfolioView       # User's holdings
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

## Gemini API Integration
- **Service**: `GeminiService.swift` - generates witty portfolio taglines
- **API Key**: Store in `Secrets.swift` (gitignored) - get from https://aistudio.google.com/app/apikey
- **Model**: `gemini-2.0-flash`
- **Usage**: LeaderboardView calls on row appear, results cached
- **Billing**: Must link Google Cloud billing for quota (free tier: 1500/day)

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
