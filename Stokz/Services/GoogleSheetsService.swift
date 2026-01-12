import Foundation

/// GoogleSheetsService handles all backend data storage using Google Sheets
/// Sheets structure:
/// - Users: id, email, displayName, photoURL, createdAt
/// - Portfolios: userId, holdings (JSON), cashBalance, initialValue, lastUpdated
/// - PriceCache: symbol, price, previousClose, timestamp
/// - NetWorthSnapshots: id, userId, netWorth, timestamp
@MainActor
class GoogleSheetsService: ObservableObject {
    
    static let shared = GoogleSheetsService()
    
    // MARK: - Configuration
    /// Google Sheets API configuration
    private let spreadsheetId = "1RaekeX5bxMnI0CTb1OsMYERY0mNDaglSVsMYnpOS8ME"
    
    // Sheet names
    private let usersSheet = "Users"
    private let portfoliosSheet = "Portfolios"
    private let priceCacheSheet = "PriceCache"
    private let snapshotsSheet = "NetWorthSnapshots"
    private let bugReportsSheet = "BugReports"
    
    private let baseURL = "https://sheets.googleapis.com/v4/spreadsheets"
    
    @Published var isLoading = false
    @Published var error: String?
    
    // Local cache
    @Published private(set) var users: [User] = []
    @Published private(set) var portfolios: [String: Portfolio] = [:] // userId -> Portfolio
    @Published private(set) var snapshots: [String: [NetWorthSnapshot]] = [:] // userId -> Snapshots
    
    private var accessToken: String?
    
    // MARK: - Authentication
    func setAccessToken(_ token: String) {
        logInfo("Access token set for Sheets API", category: .sheets)
        self.accessToken = token
    }
    
    // MARK: - Fetch All Data
    func fetchAllData() async throws {
        logInfo("Fetching all data from Google Sheets", category: .sheets)
        isLoading = true
        defer { isLoading = false }
        
        async let usersResult = fetchUsers()
        async let portfoliosResult = fetchPortfolios()
        async let snapshotsResult = fetchSnapshots()
        
        let (fetchedUsers, fetchedPortfolios, fetchedSnapshots) = try await (usersResult, portfoliosResult, snapshotsResult)
        
        self.users = fetchedUsers
        self.portfolios = fetchedPortfolios
        self.snapshots = fetchedSnapshots
        
        logSuccess("Fetched all data: \(fetchedUsers.count) users, \(fetchedPortfolios.count) portfolios", category: .sheets)
    }
    
    // MARK: - Users
    func fetchUsers() async throws -> [User] {
        logDebug("Fetching users from sheet", category: .sheets)
        let range = "\(usersSheet)!A2:H"  // Extended to include isAI, aiThesis, aiProvider
        let request = try buildAuthenticatedReadRequest(range: range)
        
        Logger.shared.net("GET", "sheets")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        Logger.shared.netOK(httpResponse?.statusCode ?? 0, "sheets")
        
        // Check for 403 - this means the token doesn't have the right scopes
        if httpResponse?.statusCode == 403 {
            logError("403 Forbidden - token may not have Sheets scope. User needs to re-authenticate.", category: .sheets)
            throw GoogleSheetsError.notAuthenticated
        }
        
        let sheetsResponse = try JSONDecoder().decode(SheetValuesResponse.self, from: data)
        
        let users = sheetsResponse.values?.compactMap { row -> User? in
            guard row.count >= 5 else { return nil }
            // Parse AI fields if present (columns F, G, H)
            let isAI = row.count > 5 ? (row[5].lowercased() == "true") : false
            let aiThesis = row.count > 6 && !row[6].isEmpty ? row[6] : nil
            let aiProvider = row.count > 7 && !row[7].isEmpty ? row[7] : nil
            
            return User(
                id: row[0],
                email: row[1],
                displayName: row[2],
                photoURL: row[3].isEmpty ? nil : row[3],
                createdAt: ISO8601DateFormatter().date(from: row[4]) ?? Date(),
                isAI: isAI,
                aiThesis: aiThesis,
                aiProvider: aiProvider
            )
        } ?? []
        
        logInfo("Fetched \(users.count) users (\(users.filter { $0.isAI }.count) AI players)", category: .sheets)
        return users
    }
    
    func saveUser(_ user: User) async throws {
        logInfo("Saving user: \(user.displayName) (id: \(user.id), isAI: \(user.isAI))", category: .sheets)
        
        // Check if user already exists in sheet - don't duplicate
        let existingUsers = try await fetchUsers()
        if existingUsers.contains(where: { $0.id == user.id }) {
            logDebug("User already exists in sheet, updating...", category: .sheets)
            // User exists - update their row
            try await updateUser(user)
            return
        }
        
        logDebug("New user - appending to sheet", category: .sheets)
        // New user - append to sheet with AI fields
        let values = [[
            user.id,
            user.email,
            user.displayName,
            user.photoURL ?? "",
            ISO8601DateFormatter().string(from: user.createdAt),
            user.isAI ? "true" : "false",
            user.aiThesis ?? "",
            user.aiProvider ?? ""
        ]]
        
        try await appendRows(sheet: usersSheet, values: values)
        logSuccess("User saved to sheet: \(user.displayName)", category: .sheets)
        
        // Update local cache
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        } else {
            users.append(user)
        }
    }
    
    /// Update an existing user's row (for AI player updates)
    func updateUser(_ user: User) async throws {
        // Find the row number for this user
        let allUsers = try await fetchUsers()
        guard let rowIndex = allUsers.firstIndex(where: { $0.id == user.id }) else {
            // User not found, save as new
            try await saveUser(user)
            return
        }
        
        // Row index is 0-based, sheet rows start at 2 (row 1 is header)
        let sheetRow = rowIndex + 2
        let range = "\(usersSheet)!A\(sheetRow):H\(sheetRow)"
        
        let values = [[
            user.id,
            user.email,
            user.displayName,
            user.photoURL ?? "",
            ISO8601DateFormatter().string(from: user.createdAt),
            user.isAI ? "true" : "false",
            user.aiThesis ?? "",
            user.aiProvider ?? ""
        ]]
        
        try await updateRows(range: range, values: values)
        logSuccess("Updated user: \(user.displayName)", category: .sheets)
        
        // Update local cache
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        }
    }
    
    // MARK: - Portfolios
    func fetchPortfolios() async throws -> [String: Portfolio] {
        logDebug("Fetching portfolios from sheet", category: .sheets)
        let range = "\(portfoliosSheet)!A2:E"
        let request = try buildAuthenticatedReadRequest(range: range)
        
        Logger.shared.net("GET", "sheets")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        Logger.shared.netOK(httpResponse?.statusCode ?? 0, "sheets")
        
        let sheetsResponse = try JSONDecoder().decode(SheetValuesResponse.self, from: data)
        
        var result: [String: Portfolio] = [:]
        var latestTimestamps: [String: Date] = [:]

        for row in sheetsResponse.values ?? [] {
            guard row.count >= 5 else { continue }
            
            let userId = row[0]
            let holdingsJSON = row[1]
            let cashBalance = Double(row[2]) ?? 0
            let initialValue = Double(row[3]) ?? 100_000
            let lastUpdated = ISO8601DateFormatter().date(from: row[4]) ?? Date()
            
            // Use the most recent row for each user (based on timestamp)
            if let existingTimestamp = latestTimestamps[userId], existingTimestamp >= lastUpdated {
                logDebug("Skipping older portfolio row for user \(userId) (existing: \(existingTimestamp), this: \(lastUpdated))", category: .sheets)
                continue
            }
            latestTimestamps[userId] = lastUpdated
            
            logDebug("Portfolio row for user \(userId): holdings JSON length=\(holdingsJSON.count), timestamp=\(lastUpdated)", category: .sheets)
            
            // Decode holdings from JSON
            var holdings: [PortfolioHolding] = []
            var hasPlaceholderPrices = false
            if let jsonData = holdingsJSON.data(using: .utf8) {
                do {
                    holdings = try JSONDecoder().decode([PortfolioHolding].self, from: jsonData)
                    logDebug("Decoded \(holdings.count) holdings for user \(userId)", category: .sheets)
                    for h in holdings {
                        logDebug("  - \(h.symbol): \(String(format: "%.4f", h.shares)) shares @ $\(String(format: "%.2f", h.entryPrice))", category: .sheets)
                        // Check for suspicious $100 placeholder prices
                        if h.entryPrice == 100.0 {
                            logWarning("⚠️ Suspicious $100 entry price for \(h.symbol) - may be placeholder!", category: .sheets)
                            hasPlaceholderPrices = true
                        }
                    }
                } catch {
                    logError("Failed to decode holdings for user \(userId): \(error)", category: .sheets)
                    logDebug("Raw holdings JSON: \(holdingsJSON.prefix(200))", category: .sheets)
                }
            }
            
            // Skip portfolios with placeholder prices if we have a better one
            if hasPlaceholderPrices && result[userId] != nil {
                logWarning("Skipping portfolio with placeholder prices for \(userId), keeping existing", category: .sheets)
                continue
            }
            
            var portfolio = Portfolio(
                id: UUID().uuidString,
                userId: userId,
                holdings: holdings,
                initialValue: initialValue
            )
            portfolio.cashBalance = cashBalance // Restore cash balance from sheet
            portfolio.lastUpdated = lastUpdated
            
            result[userId] = portfolio
        }
        
        logInfo("Fetched \(result.count) portfolios", category: .sheets)
        return result
    }
    
    func savePortfolio(_ portfolio: Portfolio) async throws {
        logInfo("Saving portfolio for user: \(portfolio.userId)", category: .sheets)
        let encoder = JSONEncoder()
        let holdingsJSON = try encoder.encode(portfolio.holdings)
        let holdingsString = String(data: holdingsJSON, encoding: .utf8) ?? "[]"
        
        let values = [[
            portfolio.userId,
            holdingsString,
            String(portfolio.cashBalance),
            String(portfolio.initialValue),
            ISO8601DateFormatter().string(from: portfolio.lastUpdated)
        ]]
        
        // Check if portfolio exists - if so, update; otherwise append
        if portfolios[portfolio.userId] != nil {
            logDebug("Updating existing portfolio row", category: .sheets)
            try await updatePortfolioRow(portfolio: portfolio, values: values[0])
        } else {
            logDebug("Appending new portfolio row", category: .sheets)
            try await appendRows(sheet: portfoliosSheet, values: values)
        }
        
        // Update local cache
        portfolios[portfolio.userId] = portfolio
        logSuccess("Portfolio saved for user: \(portfolio.userId)", category: .sheets)
    }
    
    private func updatePortfolioRow(portfolio: Portfolio, values: [String]) async throws {
        // Find row index for user
        let range = "\(portfoliosSheet)!A2:A"
        let request = try buildAuthenticatedReadRequest(range: range)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SheetValuesResponse.self, from: data)
        
        guard let rows = response.values,
              let rowIndex = rows.firstIndex(where: { $0.first == portfolio.userId }) else {
            // Portfolio not found, append instead
            try await appendRows(sheet: portfoliosSheet, values: [values])
            return
        }
        
        // Row index is 0-based, add 2 for header row and 1-based indexing
        let sheetRow = rowIndex + 2
        let updateRange = "\(portfoliosSheet)!A\(sheetRow):E\(sheetRow)"
        
        try await updateRows(range: updateRange, values: [values])
    }
    
    // MARK: - Net Worth Snapshots
    func fetchSnapshots() async throws -> [String: [NetWorthSnapshot]] {
        logDebug("Fetching net worth snapshots from sheet", category: .sheets)
        let range = "\(snapshotsSheet)!A2:D"
        let request = try buildAuthenticatedReadRequest(range: range)
        
        Logger.shared.net("GET", "sheets")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        Logger.shared.netOK(httpResponse?.statusCode ?? 0, "sheets")
        
        let sheetsResponse = try JSONDecoder().decode(SheetValuesResponse.self, from: data)
        
        var result: [String: [NetWorthSnapshot]] = [:]
        
        for row in sheetsResponse.values ?? [] {
            guard row.count >= 4 else { continue }
            
            let snapshot = NetWorthSnapshot(
                id: row[0],
                userId: row[1],
                netWorth: Double(row[2]) ?? 0,
                timestamp: ISO8601DateFormatter().date(from: row[3]) ?? Date()
            )
            
            if result[snapshot.userId] == nil {
                result[snapshot.userId] = []
            }
            result[snapshot.userId]?.append(snapshot)
        }
        
        // Sort snapshots by date
        for userId in result.keys {
            result[userId]?.sort { $0.timestamp < $1.timestamp }
        }
        
        let totalSnapshots = result.values.reduce(0) { $0 + $1.count }
        logInfo("Fetched \(totalSnapshots) snapshots for \(result.count) users", category: .sheets)
        
        return result
    }
    
    func saveSnapshot(_ snapshot: NetWorthSnapshot) async throws {
        logDebug("Saving net worth snapshot: $\(String(format: "%.2f", snapshot.netWorth)) for user \(snapshot.userId)", category: .sheets)
        let values = [[
            snapshot.id,
            snapshot.userId,
            String(snapshot.netWorth),
            ISO8601DateFormatter().string(from: snapshot.timestamp)
        ]]
        
        try await appendRows(sheet: snapshotsSheet, values: values)
        logSuccess("Snapshot saved", category: .sheets)
        
        // Update local cache
        if snapshots[snapshot.userId] == nil {
            snapshots[snapshot.userId] = []
        }
        snapshots[snapshot.userId]?.append(snapshot)
    }
    
    // Record current net worth snapshot for a user
    func recordNetWorthSnapshot(userId: String, prices: [String: Double]) async throws {
        logInfo("Recording net worth snapshot for user: \(userId)", category: .sheets)
        guard let portfolio = portfolios[userId] else {
            logWarning("No portfolio found for user \(userId) - skipping snapshot", category: .sheets)
            return
        }
        
        let netWorth = PortfolioManager.shared.calculateNetWorth(portfolio: portfolio, prices: prices)
        let snapshot = NetWorthSnapshot(userId: userId, netWorth: netWorth)
        
        try await saveSnapshot(snapshot)
    }
    
    // MARK: - Bug Reports
    func submitBugReport(_ report: BugReport) async throws {
        logInfo("Submitting bug report: \(report.title)", category: .sheets)
        
        let values = [[
            report.id,
            report.userId,
            report.userEmail,
            report.title,
            report.description,
            report.severity.rawValue,
            report.deviceInfo,
            report.appVersion,
            report.sessionSummary,
            ISO8601DateFormatter().string(from: report.timestamp),
            report.recentLogs,
            report.screenshotData ?? ""
        ]]
        
        try await appendRows(sheet: bugReportsSheet, values: values)
        logSuccess("Bug report submitted: \(report.title)", category: .sheets)
    }
    
    // MARK: - Price Cache
    func fetchPriceCache() async throws -> [String: PriceCacheEntry] {
        logDebug("Fetching price cache from sheet", category: .sheets)
        let range = "\(priceCacheSheet)!A2:D"
        let request = try buildAuthenticatedReadRequest(range: range)
        
        Logger.shared.net("GET", "sheets")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        Logger.shared.netOK(httpResponse?.statusCode ?? 0, "sheets")
        
        let sheetsResponse = try JSONDecoder().decode(SheetValuesResponse.self, from: data)
        
        var result: [String: PriceCacheEntry] = [:]
        
        for row in sheetsResponse.values ?? [] {
            guard row.count >= 4 else { continue }
            
            let entry = PriceCacheEntry(
                symbol: row[0],
                price: Double(row[1]) ?? 0,
                previousClose: Double(row[2]) ?? 0,
                timestamp: ISO8601DateFormatter().date(from: row[3]) ?? Date()
            )
            
            result[entry.symbol] = entry
        }
        
        logInfo("Fetched \(result.count) cached prices", category: .sheets)
        return result
    }
    
    func savePriceCache(_ entries: [PriceCacheEntry]) async throws {
        logInfo("Saving \(entries.count) price cache entries", category: .sheets)
        // Clear existing cache and write new data
        let values = entries.map { entry in
            [
                entry.symbol,
                String(entry.price),
                String(entry.previousClose),
                ISO8601DateFormatter().string(from: entry.timestamp)
            ]
        }
        
        let range = "\(priceCacheSheet)!A2:D"
        try await clearAndWriteRange(range: range, values: values)
        logSuccess("Price cache saved", category: .sheets)
    }
    
    // MARK: - Helper Methods
    private func buildAuthenticatedReadRequest(range: String) throws -> URLRequest {
        guard let token = accessToken else {
            logError("No access token - cannot read from sheet", category: .sheets)
            throw GoogleSheetsError.notAuthenticated
        }
        
        let components = URLComponents(string: "\(baseURL)/\(spreadsheetId)/values/\(range)")!
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    private func appendRows(sheet: String, values: [[String]]) async throws {
        guard let token = accessToken else {
            logError("No access token - cannot append to sheet", category: .sheets)
            throw GoogleSheetsError.notAuthenticated
        }
        
        let range = "\(sheet)!A:Z"
        var components = URLComponents(string: "\(baseURL)/\(spreadsheetId)/values/\(range):append")!
        components.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "RAW"),
            URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["values": values]
        request.httpBody = try JSONEncoder().encode(body)
        
        Logger.shared.net("POST", "sheets")
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid response from append request", category: .sheets)
            throw GoogleSheetsError.requestFailed
        }
        
        Logger.shared.netOK(httpResponse.statusCode, "sheets")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "no body"
            logError("Append failed with status \(httpResponse.statusCode): \(errorBody)", category: .sheets)
            throw GoogleSheetsError.requestFailed
        }
    }
    
    private func updateRows(range: String, values: [[String]]) async throws {
        guard let token = accessToken else {
            logError("No access token - cannot update sheet", category: .sheets)
            throw GoogleSheetsError.notAuthenticated
        }
        
        var components = URLComponents(string: "\(baseURL)/\(spreadsheetId)/values/\(range)")!
        components.queryItems = [
            URLQueryItem(name: "valueInputOption", value: "RAW")
        ]
        
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["values": values]
        request.httpBody = try JSONEncoder().encode(body)
        
        Logger.shared.net("PUT", "sheets")
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logError("Invalid response from update request", category: .sheets)
            throw GoogleSheetsError.requestFailed
        }
        
        Logger.shared.netOK(httpResponse.statusCode, "sheets")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            logError("Update failed with status \(httpResponse.statusCode)", category: .sheets)
            throw GoogleSheetsError.requestFailed
        }
    }
    
    private func clearAndWriteRange(range: String, values: [[String]]) async throws {
        guard let token = accessToken else {
            logError("No access token - cannot clear/write sheet", category: .sheets)
            throw GoogleSheetsError.notAuthenticated
        }
        
        logDebug("Clearing range: \(range)", category: .sheets)
        
        // Clear existing data
        let clearURL = URL(string: "\(baseURL)/\(spreadsheetId)/values/\(range):clear")!
        var clearRequest = URLRequest(url: clearURL)
        clearRequest.httpMethod = "POST"
        clearRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        Logger.shared.net("POST", "sheets")
        _ = try await URLSession.shared.data(for: clearRequest)
        
        // Write new data
        if !values.isEmpty {
            logDebug("Writing \(values.count) rows to \(range)", category: .sheets)
            try await updateRows(range: range, values: values)
        }
    }
    
    // MARK: - Get User Portfolio
    func getPortfolio(for userId: String) -> Portfolio {
        return portfolios[userId] ?? PortfolioManager.shared.createInitialPortfolio(for: userId)
    }
    
    // MARK: - Get Snapshots for Chart
    func getSnapshots(for userId: String, in range: TimeRange) -> [ChartDataPoint] {
        guard let userSnapshots = snapshots[userId] else { return [] }
        
        let startDate = range.startDate
        return userSnapshots
            .filter { $0.timestamp >= startDate }
            .map { ChartDataPoint(date: $0.timestamp, value: $0.netWorth) }
    }
}

// MARK: - Response Models
struct SheetValuesResponse: Codable {
    let range: String?
    let majorDimension: String?
    let values: [[String]]?
}

// MARK: - Errors
enum GoogleSheetsError: Error, LocalizedError {
    case notAuthenticated
    case requestFailed
    case invalidResponse
    case userNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Google"
        case .requestFailed:
            return "Request to Google Sheets failed"
        case .invalidResponse:
            return "Invalid response from Google Sheets"
        case .userNotFound:
            return "User not found"
        }
    }
}

// MARK: - Mock Data for Development
extension GoogleSheetsService {
    func loadMockData() {
        // Mock users
        users = [
            User(id: "user1", email: "alice@example.com", displayName: "Alice", photoURL: nil, createdAt: Date()),
            User(id: "user2", email: "bob@example.com", displayName: "Bob", photoURL: nil, createdAt: Date()),
            User(id: "user3", email: "charlie@example.com", displayName: "Charlie", photoURL: nil, createdAt: Date())
        ]
        
        // Mock portfolios
        let aliceHoldings = [
            PortfolioHolding(id: "h1", symbol: "AAPL", shares: 100, entryPrice: 150, entryDate: Date()),
            PortfolioHolding(id: "h2", symbol: "GOOGL", shares: 50, entryPrice: 140, entryDate: Date()),
            PortfolioHolding(id: "h3", symbol: "MSFT", shares: 80, entryPrice: 380, entryDate: Date())
        ]
        
        let bobHoldings = [
            PortfolioHolding(id: "h4", symbol: "TSLA", shares: 150, entryPrice: 250, entryDate: Date()),
            PortfolioHolding(id: "h5", symbol: "NVDA", shares: 100, entryPrice: 500, entryDate: Date())
        ]
        
        let charlieHoldings = [
            PortfolioHolding(id: "h6", symbol: "AAPL", shares: 200, entryPrice: 155, entryDate: Date()),
            PortfolioHolding(id: "h7", symbol: "AMZN", shares: 60, entryPrice: 185, entryDate: Date())
        ]
        
        portfolios = [
            "user1": Portfolio(id: "p1", userId: "user1", holdings: aliceHoldings, initialValue: 100_000),
            "user2": Portfolio(id: "p2", userId: "user2", holdings: bobHoldings, initialValue: 100_000),
            "user3": Portfolio(id: "p3", userId: "user3", holdings: charlieHoldings, initialValue: 100_000)
        ]
        
        // Mock snapshots
        let calendar = Calendar.current
        let now = Date()
        
        func generateSnapshots(userId: String, startValue: Double, volatility: Double) -> [NetWorthSnapshot] {
            var snaps: [NetWorthSnapshot] = []
            var value = startValue
            
            for i in stride(from: 30, through: 0, by: -1) {
                if let date = calendar.date(byAdding: .day, value: -i, to: now) {
                    let change = Double.random(in: -volatility...volatility)
                    value = max(50_000, value + change)
                    snaps.append(NetWorthSnapshot(userId: userId, netWorth: value, timestamp: date))
                }
            }
            return snaps
        }
        
        snapshots = [
            "user1": generateSnapshots(userId: "user1", startValue: 100_000, volatility: 2000),
            "user2": generateSnapshots(userId: "user2", startValue: 100_000, volatility: 3000),
            "user3": generateSnapshots(userId: "user3", startValue: 100_000, volatility: 1500)
        ]
    }
}
