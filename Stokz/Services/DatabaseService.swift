import Foundation
import SQLite3

/// DatabaseService provides SQLite-based local caching for offline support and faster startup
/// Uses raw SQLite3 to avoid external dependencies
@MainActor
class DatabaseService: ObservableObject {
    
    static let shared = DatabaseService()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    // MARK: - Schema Version
    // Bump this number to drop and recreate the database on next launch
    // This avoids complex migration logic - just bump when schema changes
    private static let schemaVersion = 1
    
    // MARK: - Initialization
    
    private init() {
        // Get the documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        dbPath = documentsPath.appendingPathComponent("stokz_cache.sqlite").path
        
        logInfo("📦 Database path: \(dbPath)", category: .app)
        
        // Open/create database
        if sqlite3_open(dbPath, &db) == SQLITE_OK {
            logSuccess("📦 Database opened successfully", category: .app)
            
            // Check schema version and drop if outdated
            if !validateSchemaVersion() {
                dropAndRecreateDatabase()
            }
            
            createTables()
        } else {
            logError("📦 Failed to open database", category: .app)
        }
    }
    
    deinit {
        sqlite3_close(db)
    }
    
    // MARK: - Schema Version Management
    
    /// Check if the stored schema version matches current version
    private func validateSchemaVersion() -> Bool {
        // Create version table if it doesn't exist
        let createVersionSQL = "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);"
        executeSQL(createVersionSQL)
        
        // Read stored version
        let querySQL = "SELECT version FROM schema_version LIMIT 1;"
        var statement: OpaquePointer?
        var storedVersion: Int = 0
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                storedVersion = Int(sqlite3_column_int(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        if storedVersion == Self.schemaVersion {
            logInfo("📦 Schema version \(storedVersion) is current", category: .app)
            return true
        } else {
            logWarning("📦 Schema version mismatch: stored=\(storedVersion), current=\(Self.schemaVersion)", category: .app)
            return false
        }
    }
    
    /// Drop all tables and recreate with current schema
    private func dropAndRecreateDatabase() {
        logInfo("📦 Dropping database due to schema version change", category: .app)
        
        // Drop all data tables
        executeSQL("DROP TABLE IF EXISTS users;")
        executeSQL("DROP TABLE IF EXISTS portfolios;")
        executeSQL("DROP TABLE IF EXISTS price_cache;")
        executeSQL("DROP TABLE IF EXISTS snapshots;")
        executeSQL("DROP TABLE IF EXISTS metadata;")
        executeSQL("DROP TABLE IF EXISTS schema_version;")
        
        // Create fresh version table and set current version
        executeSQL("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);")
        executeSQL("INSERT OR REPLACE INTO schema_version (version) VALUES (\(Self.schemaVersion));")
        
        logSuccess("📦 Database dropped and schema version set to \(Self.schemaVersion)", category: .app)
    }
    
    // MARK: - Table Creation
    
    private func createTables() {
        // Users table
        let createUsersSQL = """
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                email TEXT NOT NULL,
                displayName TEXT NOT NULL,
                photoURL TEXT,
                createdAt TEXT NOT NULL,
                isAI INTEGER DEFAULT 0,
                aiThesis TEXT,
                aiProvider TEXT,
                ownerId TEXT,
                cachedAt TEXT NOT NULL
            );
        """
        
        // Portfolios table
        let createPortfoliosSQL = """
            CREATE TABLE IF NOT EXISTS portfolios (
                id TEXT PRIMARY KEY,
                userId TEXT NOT NULL UNIQUE,
                holdingsJSON TEXT NOT NULL,
                cashBalance REAL NOT NULL,
                initialValue REAL NOT NULL,
                lastUpdated TEXT NOT NULL,
                cachedAt TEXT NOT NULL
            );
        """
        
        // Price cache table
        let createPriceCacheSQL = """
            CREATE TABLE IF NOT EXISTS price_cache (
                symbol TEXT PRIMARY KEY,
                price REAL NOT NULL,
                previousClose REAL NOT NULL,
                timestamp TEXT NOT NULL,
                cachedAt TEXT NOT NULL
            );
        """
        
        // Net worth snapshots table
        let createSnapshotsSQL = """
            CREATE TABLE IF NOT EXISTS snapshots (
                id TEXT PRIMARY KEY,
                userId TEXT NOT NULL,
                netWorth REAL NOT NULL,
                timestamp TEXT NOT NULL,
                cachedAt TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_snapshots_userId ON snapshots(userId);
        """
        
        // Metadata table for cache timestamps
        let createMetadataSQL = """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
        """
        
        executeSQL(createUsersSQL)
        executeSQL(createPortfoliosSQL)
        executeSQL(createPriceCacheSQL)
        executeSQL(createSnapshotsSQL)
        executeSQL(createMetadataSQL)
        
        logSuccess("📦 Database tables created/verified", category: .app)
    }
    
    private func executeSQL(_ sql: String) {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            if let error = errorMessage {
                logError("📦 SQL Error: \(String(cString: error))", category: .app)
                sqlite3_free(errorMessage)
            }
        }
    }
    
    // MARK: - Date Formatting
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    // MARK: - Users CRUD
    
    func saveUsers(_ users: [User]) {
        logInfo("📦 Saving \(users.count) users to cache", category: .app)
        
        let now = dateFormatter.string(from: Date())
        
        // Use a transaction for better performance
        executeSQL("BEGIN TRANSACTION;")
        
        // Clear existing users
        executeSQL("DELETE FROM users;")
        
        let insertSQL = """
            INSERT OR REPLACE INTO users (id, email, displayName, photoURL, createdAt, isAI, aiThesis, aiProvider, ownerId, cachedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            for user in users {
                sqlite3_bind_text(statement, 1, (user.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (user.email as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (user.displayName as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 4, ((user.photoURL ?? "") as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 5, (dateFormatter.string(from: user.createdAt) as NSString).utf8String, -1, nil)
                sqlite3_bind_int(statement, 6, user.isAI ? 1 : 0)
                sqlite3_bind_text(statement, 7, ((user.aiThesis ?? "") as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 8, ((user.aiProvider ?? "") as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 9, ((user.ownerId ?? "") as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 10, (now as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    logError("📦 Failed to save user: \(user.id)", category: .app)
                }
                sqlite3_reset(statement)
            }
        }
        sqlite3_finalize(statement)
        
        executeSQL("COMMIT;")
        
        // Update metadata
        saveMetadata(key: "users_cached_at", value: now)
        
        logSuccess("📦 Saved \(users.count) users to cache", category: .app)
    }
    
    func loadUsers() -> [User] {
        var users: [User] = []
        
        let querySQL = "SELECT id, email, displayName, photoURL, createdAt, isAI, aiThesis, aiProvider, ownerId FROM users;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let email = String(cString: sqlite3_column_text(statement, 1))
                let displayName = String(cString: sqlite3_column_text(statement, 2))
                let photoURLStr = String(cString: sqlite3_column_text(statement, 3))
                let createdAtStr = String(cString: sqlite3_column_text(statement, 4))
                let isAI = sqlite3_column_int(statement, 5) == 1
                let aiThesisStr = String(cString: sqlite3_column_text(statement, 6))
                let aiProviderStr = String(cString: sqlite3_column_text(statement, 7))
                let ownerIdStr = String(cString: sqlite3_column_text(statement, 8))
                
                let user = User(
                    id: id,
                    email: email,
                    displayName: displayName,
                    photoURL: photoURLStr.isEmpty ? nil : photoURLStr,
                    createdAt: dateFormatter.date(from: createdAtStr) ?? Date(),
                    isAI: isAI,
                    aiThesis: aiThesisStr.isEmpty ? nil : aiThesisStr,
                    aiProvider: aiProviderStr.isEmpty ? nil : aiProviderStr,
                    ownerId: ownerIdStr.isEmpty ? nil : ownerIdStr
                )
                users.append(user)
            }
        }
        sqlite3_finalize(statement)
        
        logInfo("📦 Loaded \(users.count) users from cache", category: .app)
        return users
    }
    
    // MARK: - Portfolios CRUD
    
    func savePortfolios(_ portfolios: [String: Portfolio]) {
        logInfo("📦 Saving \(portfolios.count) portfolios to cache", category: .app)
        
        let now = dateFormatter.string(from: Date())
        let encoder = JSONEncoder()
        
        executeSQL("BEGIN TRANSACTION;")
        executeSQL("DELETE FROM portfolios;")
        
        let insertSQL = """
            INSERT OR REPLACE INTO portfolios (id, userId, holdingsJSON, cashBalance, initialValue, lastUpdated, cachedAt)
            VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            for (userId, portfolio) in portfolios {
                guard let holdingsData = try? encoder.encode(portfolio.holdings),
                      let holdingsJSON = String(data: holdingsData, encoding: .utf8) else {
                    continue
                }
                
                sqlite3_bind_text(statement, 1, (portfolio.id as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 2, (userId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (holdingsJSON as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 4, portfolio.cashBalance)
                sqlite3_bind_double(statement, 5, portfolio.initialValue)
                sqlite3_bind_text(statement, 6, (dateFormatter.string(from: portfolio.lastUpdated) as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 7, (now as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    logError("📦 Failed to save portfolio for user: \(userId)", category: .app)
                }
                sqlite3_reset(statement)
            }
        }
        sqlite3_finalize(statement)
        
        executeSQL("COMMIT;")
        saveMetadata(key: "portfolios_cached_at", value: now)
        
        logSuccess("📦 Saved \(portfolios.count) portfolios to cache", category: .app)
    }
    
    func loadPortfolios() -> [String: Portfolio] {
        var portfolios: [String: Portfolio] = [:]
        let decoder = JSONDecoder()
        
        let querySQL = "SELECT id, userId, holdingsJSON, cashBalance, initialValue, lastUpdated FROM portfolios;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let userId = String(cString: sqlite3_column_text(statement, 1))
                let holdingsJSON = String(cString: sqlite3_column_text(statement, 2))
                let cashBalance = sqlite3_column_double(statement, 3)
                let initialValue = sqlite3_column_double(statement, 4)
                let lastUpdatedStr = String(cString: sqlite3_column_text(statement, 5))
                
                guard let holdingsData = holdingsJSON.data(using: .utf8),
                      let holdings = try? decoder.decode([PortfolioHolding].self, from: holdingsData) else {
                    continue
                }
                
                var portfolio = Portfolio(
                    id: id,
                    userId: userId,
                    holdings: holdings,
                    cashBalance: cashBalance,
                    initialValue: initialValue
                )
                portfolio.lastUpdated = dateFormatter.date(from: lastUpdatedStr) ?? Date()
                
                portfolios[userId] = portfolio
            }
        }
        sqlite3_finalize(statement)
        
        logInfo("📦 Loaded \(portfolios.count) portfolios from cache", category: .app)
        return portfolios
    }
    
    // MARK: - Price Cache CRUD
    
    func savePriceCache(_ prices: [String: PriceCacheEntry]) {
        logInfo("📦 Saving \(prices.count) price entries to cache", category: .app)
        
        let now = dateFormatter.string(from: Date())
        
        executeSQL("BEGIN TRANSACTION;")
        executeSQL("DELETE FROM price_cache;")
        
        let insertSQL = """
            INSERT OR REPLACE INTO price_cache (symbol, price, previousClose, timestamp, cachedAt)
            VALUES (?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            for (symbol, entry) in prices {
                sqlite3_bind_text(statement, 1, (symbol as NSString).utf8String, -1, nil)
                sqlite3_bind_double(statement, 2, entry.price)
                sqlite3_bind_double(statement, 3, entry.previousClose)
                sqlite3_bind_text(statement, 4, (dateFormatter.string(from: entry.timestamp) as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 5, (now as NSString).utf8String, -1, nil)
                
                if sqlite3_step(statement) != SQLITE_DONE {
                    logError("📦 Failed to save price for: \(symbol)", category: .app)
                }
                sqlite3_reset(statement)
            }
        }
        sqlite3_finalize(statement)
        
        executeSQL("COMMIT;")
        saveMetadata(key: "prices_cached_at", value: now)
        
        logSuccess("📦 Saved \(prices.count) price entries to cache", category: .app)
    }
    
    func loadPriceCache() -> [String: PriceCacheEntry] {
        var prices: [String: PriceCacheEntry] = [:]
        
        let querySQL = "SELECT symbol, price, previousClose, timestamp FROM price_cache;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let symbol = String(cString: sqlite3_column_text(statement, 0))
                let price = sqlite3_column_double(statement, 1)
                let previousClose = sqlite3_column_double(statement, 2)
                let timestampStr = String(cString: sqlite3_column_text(statement, 3))
                
                let entry = PriceCacheEntry(
                    symbol: symbol,
                    price: price,
                    previousClose: previousClose,
                    timestamp: dateFormatter.date(from: timestampStr) ?? Date()
                )
                prices[symbol] = entry
            }
        }
        sqlite3_finalize(statement)
        
        logInfo("📦 Loaded \(prices.count) price entries from cache", category: .app)
        return prices
    }
    
    // MARK: - Snapshots CRUD
    
    func saveSnapshots(_ snapshots: [String: [NetWorthSnapshot]]) {
        let totalCount = snapshots.values.reduce(0) { $0 + $1.count }
        logInfo("📦 Saving \(totalCount) snapshots to cache", category: .app)
        
        let now = dateFormatter.string(from: Date())
        
        executeSQL("BEGIN TRANSACTION;")
        executeSQL("DELETE FROM snapshots;")
        
        let insertSQL = """
            INSERT OR REPLACE INTO snapshots (id, userId, netWorth, timestamp, cachedAt)
            VALUES (?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            for (_, userSnapshots) in snapshots {
                for snapshot in userSnapshots {
                    sqlite3_bind_text(statement, 1, (snapshot.id as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 2, (snapshot.userId as NSString).utf8String, -1, nil)
                    sqlite3_bind_double(statement, 3, snapshot.netWorth)
                    sqlite3_bind_text(statement, 4, (dateFormatter.string(from: snapshot.timestamp) as NSString).utf8String, -1, nil)
                    sqlite3_bind_text(statement, 5, (now as NSString).utf8String, -1, nil)
                    
                    if sqlite3_step(statement) != SQLITE_DONE {
                        logError("📦 Failed to save snapshot: \(snapshot.id)", category: .app)
                    }
                    sqlite3_reset(statement)
                }
            }
        }
        sqlite3_finalize(statement)
        
        executeSQL("COMMIT;")
        saveMetadata(key: "snapshots_cached_at", value: now)
        
        logSuccess("📦 Saved \(totalCount) snapshots to cache", category: .app)
    }
    
    func loadSnapshots() -> [String: [NetWorthSnapshot]] {
        var snapshots: [String: [NetWorthSnapshot]] = [:]
        
        let querySQL = "SELECT id, userId, netWorth, timestamp FROM snapshots ORDER BY userId, timestamp;"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(statement, 0))
                let userId = String(cString: sqlite3_column_text(statement, 1))
                let netWorth = sqlite3_column_double(statement, 2)
                let timestampStr = String(cString: sqlite3_column_text(statement, 3))
                
                let snapshot = NetWorthSnapshot(
                    id: id,
                    userId: userId,
                    netWorth: netWorth,
                    timestamp: dateFormatter.date(from: timestampStr) ?? Date()
                )
                
                if snapshots[userId] == nil {
                    snapshots[userId] = []
                }
                snapshots[userId]?.append(snapshot)
            }
        }
        sqlite3_finalize(statement)
        
        let totalCount = snapshots.values.reduce(0) { $0 + $1.count }
        logInfo("📦 Loaded \(totalCount) snapshots from cache", category: .app)
        return snapshots
    }
    
    // MARK: - Metadata
    
    private func saveMetadata(key: String, value: String) {
        let insertSQL = "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?);"
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (value as NSString).utf8String, -1, nil)
            sqlite3_step(statement)
        }
        sqlite3_finalize(statement)
    }
    
    func getMetadata(key: String) -> String? {
        let querySQL = "SELECT value FROM metadata WHERE key = ?;"
        var statement: OpaquePointer?
        var result: String?
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, (key as NSString).utf8String, -1, nil)
            if sqlite3_step(statement) == SQLITE_ROW {
                result = String(cString: sqlite3_column_text(statement, 0))
            }
        }
        sqlite3_finalize(statement)
        
        return result
    }
    
    // MARK: - Cache Age Check
    
    func getCacheAge() -> TimeInterval? {
        guard let cachedAtStr = getMetadata(key: "users_cached_at"),
              let cachedAt = dateFormatter.date(from: cachedAtStr) else {
            return nil
        }
        return Date().timeIntervalSince(cachedAt)
    }
    
    func isCacheValid(maxAge: TimeInterval = 3600) -> Bool {
        guard let age = getCacheAge() else { return false }
        return age < maxAge
    }
    
    // MARK: - Clear Cache
    
    func clearCache() {
        logInfo("📦 Clearing all cached data", category: .app)
        executeSQL("DELETE FROM users;")
        executeSQL("DELETE FROM portfolios;")
        executeSQL("DELETE FROM price_cache;")
        executeSQL("DELETE FROM snapshots;")
        executeSQL("DELETE FROM metadata;")
        logSuccess("📦 Cache cleared", category: .app)
    }
    
    // MARK: - Save All (convenience method)
    
    func saveAllData(users: [User], portfolios: [String: Portfolio], snapshots: [String: [NetWorthSnapshot]], priceCache: [String: PriceCacheEntry]) {
        saveUsers(users)
        savePortfolios(portfolios)
        saveSnapshots(snapshots)
        savePriceCache(priceCache)
    }
}
