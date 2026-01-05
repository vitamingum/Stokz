# Stokz 📈

A social stock-trading game (paper trading) for friends, built with SwiftUI.

## Features

- **Paper Trading**: Each user starts with $100,000 virtual cash
- **100% Invested**: Portfolios are always fully invested (no cash sitting idle)
- **Market-Value Based**: Holdings float automatically as prices move
- **Social Competition**: See friends' portfolios and compete on the leaderboard
- **Real-Time Prices**: Live stock prices from Finnhub API

## Screenshots

The app features an Apple Stocks-style UI with:

1. **Portfolio View** - Your stocks with allocation percentages
2. **Players View** - All friends in the game
3. **Stocks View** - Union of all stocks across all players
4. **Leaderboard** - Rankings by net worth

## Portfolio Rules

### Adding a Stock
- Portfolio rebalances equally across all stocks at current market prices
- Entry price is recorded for performance tracking

### Price Changes
- Affect both net worth and allocation %
- If one stock 5×'s, its % of portfolio increases accordingly (no auto-rebalancing)

### Adjusting Allocation
- Setting one stock to X% triggers an instant rebalance
- Remaining stocks are scaled proportionally to their current market values

## Setup Instructions

### 1. Google Cloud Console Setup

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable the following APIs:
   - Google Sheets API
   - Google Sign-In
4. Configure OAuth consent screen
5. Create OAuth 2.0 credentials (iOS application)
6. Copy the Client ID

### 2. Google Sheets Setup

Create a new Google Sheet with the following sheets (tabs):

**Users** (columns A-E):
| id | email | displayName | photoURL | createdAt |
|----|-------|-------------|----------|-----------|

**Portfolios** (columns A-E):
| userId | holdings (JSON) | cashBalance | initialValue | lastUpdated |
|--------|-----------------|-------------|--------------|-------------|

**PriceCache** (columns A-D):
| symbol | price | previousClose | timestamp |
|--------|-------|---------------|-----------|

**NetWorthSnapshots** (columns A-D):
| id | userId | netWorth | timestamp |
|----|--------|----------|-----------|

### 3. Finnhub API Key

1. Go to [Finnhub.io](https://finnhub.io/)
2. Sign up for a free account
3. Copy your API key

### 4. Configure the App

Update the following files with your credentials:

**`Stokz/Services/AuthenticationService.swift`**:
```swift
private let clientId = "YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com"
private let redirectURI = "com.googleusercontent.apps.YOUR_CLIENT_ID:/oauth2redirect"
```

**`Stokz/Services/GoogleSheetsService.swift`**:
```swift
private let spreadsheetId = "YOUR_SPREADSHEET_ID"
private let apiKey = "YOUR_API_KEY"
```

**`Stokz/Services/StockPriceService.swift`**:
```swift
private let finnhubApiKey = "YOUR_FINNHUB_API_KEY"
```

**`Stokz/Info.plist`**:
Update the URL scheme with your Google Client ID.

### 5. Build and Run

1. Open `Stokz.xcodeproj` in Xcode 15+
2. Select your target device or simulator
3. Build and run (⌘R)

## Architecture

```
Stokz/
├── StokzApp.swift           # App entry point
├── ContentView.swift        # Main tab navigation
├── AppState.swift           # Global app state manager
├── Models/
│   └── Models.swift         # Data models
├── Services/
│   ├── PortfolioManager.swift    # Portfolio math & rebalancing
│   ├── GoogleSheetsService.swift # Backend data storage
│   ├── StockPriceService.swift   # Live price fetching
│   └── AuthenticationService.swift # Google OAuth
├── Views/
│   ├── PortfolioView.swift       # My portfolio
│   ├── UsersView.swift           # All players
│   ├── UserPortfolioView.swift   # View other's portfolio
│   ├── StocksView.swift          # All stocks
│   ├── LeaderboardView.swift     # Rankings
│   ├── PerformanceChartView.swift # Charts
│   ├── AddStockView.swift        # Add stock sheet
│   └── AdjustAllocationView.swift # Adjust allocation
├── Components/
│   ├── StockRowView.swift        # Stock list row
│   └── UserRowView.swift         # User list row
└── Extensions.swift              # Utility extensions
```

## Key Classes

### PortfolioManager
Handles all portfolio calculations:
- `addStock()` - Add new stock and rebalance equally
- `removeStock()` - Remove stock and redistribute
- `adjustAllocation()` - Set specific % for one stock
- `rebalanceEqually()` - Reset to equal weights
- `calculateNetWorth()` - Get current portfolio value

### AppState
Central state management:
- Coordinates between all services
- Manages current user session
- Updates derived state (leaderboard, stock lists)
- Handles price refresh timer

## Development Mode

The app includes mock data for development:
- 3 sample users with portfolios
- 10 popular stocks with prices
- 30 days of historical snapshots

Mock data loads automatically in DEBUG builds. For production, configure real credentials.

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Dependencies

None! Built entirely with:
- SwiftUI
- Swift Charts
- Foundation
- AuthenticationServices
- CryptoKit

## License

MIT License - feel free to use for learning or building your own version!

## Contributing

Pull requests welcome! Please ensure:
- Code follows existing style
- All portfolio math is tested for correctness
- UI matches Apple Stocks aesthetic
