# AI Context - Stokz

## Project Layout (~35 Swift files, ~10,000 LOC)

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
│   ├── StockDataService    # Company info from JSON bundle (1005 stocks)
│   ├── DatabaseService     # SQLite local cache for offline/fast startup
│   ├── PortfolioManager    # Buy/sell logic
│   ├── AuthenticationService
│   ├── AIService           # Multi-provider LLM (Gemini/OpenAI/Anthropic/Grok)
│   ├── StockScreenerService # TALL BOY AI screener (map-reduce pattern)
│   ├── BugReportService    # Bug reporting
│   ├── Secrets.swift       # API keys (GITIGNORED)
│   └── Logger
├── Views/
│   ├── PortfolioView       # User's holdings + AI screener chat
│   ├── StockScreenerChatView # TALL BOY input + results + detail views
│   ├── LeaderboardView     # Ranked players + AI taglines
│   ├── UsersView           # All players
│   ├── StocksView          # All stocks union
│   ├── SettingsView        # Debug console + AI provider selection
│   ├── AddStockView        # Search + add stocks
│   ├── StockDiscoveryView  # AI company info cards
│   ├── APIKeySetupView     # Multi-provider API key setup
│   ├── BugReportView       # Bug reporting UI
│   └── (5 more views)
├── Components/
│   ├── StockRowView
│   └── UserRowView
├── Config/
│   └── Development.xcconfig # Team ID (gitignored per-dev)
├── Extensions.swift        # Currency/date formatters
└── stock_data_bundle.json  # 1005 companies (788KB)
```

## Co-Development Setup (xcconfig)

Team ID is managed via xcconfig to avoid merge conflicts:

1. **Development.xcconfig** (gitignored) - each dev creates locally:
   ```
   DEVELOPMENT_TEAM = YOUR_TEAM_ID
   CODE_SIGN_STYLE = Automatic
   ```

2. **Development.xcconfig.template** - committed template for new devs

3. **project.pbxproj** references xcconfig via `baseConfigurationReference`

## AIService (Multi-Provider LLM)

**Service**: `AIService.swift` - unified interface for multiple LLM providers

**Supported Providers**:
- Gemini (gemini-2.0-flash) - default, has free tier
- OpenAI (gpt-4o)
- Anthropic (claude-3-5-sonnet)
- Grok (grok-2-latest)

**Key Methods**:
- `chat(system:user:)` - single-turn chat
- `selectedProvider` - current provider (persisted in UserDefaults)
- `setAPIKey(for:key:)` - store API key securely

**Usage**: All AI features route through AIService (taglines, screener, chat)

## DatabaseService (Local SQLite Cache)

**Service**: `DatabaseService.swift` - SQLite-based local caching for offline support and faster startup

**Purpose**:
- Cache users, portfolios, snapshots, and prices locally
- Enable instant app startup with cached data (network refresh happens in background)
- No external dependencies - uses raw SQLite3

**Schema Version (Nonce)**:
```swift
private static let schemaVersion = 1  // Bump to drop & recreate DB
```
When `schemaVersion` changes, the entire database is dropped and recreated. This avoids complex migration logic - just bump the version when schema/data format changes.

**Tables**:
- `users` - cached user profiles (including AI players)
- `portfolios` - cached portfolio holdings (JSON-encoded)
- `price_cache` - cached stock prices
- `snapshots` - net worth history
- `metadata` - cache timestamps
- `schema_version` - version tracking for nonce

**Key Methods**:
- `saveAllData(users:portfolios:snapshots:priceCache:)` - persist after network fetch
- `loadUsers()`, `loadPortfolios()`, `loadPriceCache()`, `loadSnapshots()` - restore on startup
- `clearCache()` - manual cache clear
- `isCacheValid(maxAge:)` - check if cache is stale

**Integration Points**:
- `AppState.initialize()` calls `loadCachedData()` before network calls
- `AppState.loadAllData()` calls `saveDataToCache()` after successful fetch
- `GoogleSheetsService.loadFromCache()` populates service from cached data
- `StockPriceService.loadFromCache()` restores price cache

## TALL BOY AI Stock Screener

**Service**: `StockScreenerService.swift`

**Map-Reduce Pattern**:
1. User prompt → criteria generation
2. Batch evaluation (25 stocks/batch, 5 parallel) → ScoredStock list
3. Live feed shows progress + emerging leaders
4. Final analysis on top 30 → StockPick results

**UI Components** (in `StockScreenerChatView.swift`):
- `StockScreenerChatView` - main input + results
- `StockPickRow` - result row (tappable)
- `StockPickDetailView` - full thesis + chat for final picks
- `ContenderChip` - tappable emerging leader during screening
- `ContenderDetailView` - early-look thesis + chat while screening continues

**Conversation Support**:
- `ChatMessage` struct (role, content, timestamp)
- `conversations` dictionary keyed by ticker
- `askFollowUp()` sends full history with each request
- Chat bubbles: green=user, dark=assistant

**Key State**:
- `@Published isScreening` - screening in progress
- `@Published progress` - ScreeningProgress enum
- `@Published topScorers` - [ScoredStock] emerging leaders
- `@Published results` - [StockPick] final results
- `lastPrompt` - stored for detail view context

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

## Dev Workflow (Build + Deploy + Logs)

**Build only (check errors):**
```bash
cd /Users/charlesburns/Stokz && \
xcodebuild -scheme Stokz -sdk iphoneos -configuration Debug build -quiet 2>&1 | grep -E "error:" | head -10
```

**Build + install + launch:**
```bash
cd /Users/charlesburns/Stokz && \
xcodebuild -scheme Stokz -sdk iphoneos -configuration Debug build -quiet && \
xcrun devicectl device install app --device 00008150-001E08190A38401C \
  /Users/charlesburns/Library/Developer/Xcode/DerivedData/Stokz-bazhfupqpoomaxbihkzdvidadyrf/Build/Products/Debug-iphoneos/Stokz.app && \
xcrun devicectl device process launch --device 00008150-001E08190A38401C \
  --terminate-existing com.stokz.app
```

**With live console (Ctrl-C to exit):**
```bash
xcrun devicectl device process launch --device 00008150-001E08190A38401C \
  --terminate-existing --console com.stokz.app 2>&1 | tee /tmp/stokz_log.txt
```

**Check logs:** `cat /tmp/stokz_log.txt | tail -100`

## Key IDs
- **Bundle**: `com.stokz.app`
- **Device (Charles)**: `00008150-001E08190A38401C`
- **Team (Charles)**: `MSW9JQ3H2Q`
- **App Store**: `6757373916`
- **DerivedData**: `Stokz-bazhfupqpoomaxbihkzdvidadyrf`

## Fastlane (TestFlight)
```bash
cd /Users/charlesburns/Stokz && fastlane beta  # Build + upload to TestFlight
```

## AI Stock Data Pipeline
```bash
cd /Users/charlesburns/Stokz/pipeline
.venv/bin/python run_russell3000_pipeline.py  # Options: --skip-wiki, --skip-facts
```

Outputs `ios_bundle/stock_data_bundle.json` with facts + similarity for all stocks.
