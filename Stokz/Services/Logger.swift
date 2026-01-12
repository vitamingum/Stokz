import Foundation
import os.log

/// Centralized logging for Stokz app
enum LogCategory: String {
    case auth = "Auth"
    case sheets = "Sheets"
    case stocks = "Stocks"
    case portfolio = "Port"
    case app = "App"
    case network = "Net"
    case ui = "UI"
    case llm = "LLM"
}

enum LogLevel: String {
    case debug = "🔍"
    case info = "ℹ️"
    case warning = "⚠️"
    case error = "❌"
    case success = "✅"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    
    var display: String {
        let t = Self.timeFormatter.string(from: time)
        return "\(level.rawValue) [\(t)][\(category.rawValue)] \(message)"
    }
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

@MainActor
final class Logger: ObservableObject {
    static let shared = Logger()
    
    private let subsystem = "com.stokz.app"
    private var loggers: [LogCategory: OSLog] = [:]
    
    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 500
    
    private init() {
        for category in [LogCategory.auth, .sheets, .stocks, .portfolio, .app, .network, .ui, .llm] {
            loggers[category] = OSLog(subsystem: subsystem, category: category.rawValue)
        }
    }
    
    func debug(_ message: String, category: LogCategory = .app) {
        log(message, level: .debug, category: category)
    }
    
    func info(_ message: String, category: LogCategory = .app) {
        log(message, level: .info, category: category)
    }
    
    func warning(_ message: String, category: LogCategory = .app) {
        log(message, level: .warning, category: category)
    }
    
    func error(_ message: String, category: LogCategory = .app) {
        log(message, level: .error, category: category)
    }
    
    func success(_ message: String, category: LogCategory = .app) {
        log(message, level: .success, category: category)
    }
    
    func net(_ method: String, _ url: String) {
        info("\(method) \(url.suffix(40))", category: .network)
    }
    
    func netOK(_ code: Int, _ url: String) {
        success("\(code) \(url.suffix(30))", category: .network)
    }
    
    func netErr(_ err: String) {
        error(err.prefix(60).description, category: .network)
    }
    
    func clear() {
        entries.removeAll()
    }
    
    /// Export recent logs for bug reports (last N entries, truncated)
    func exportRecentLogs(count: Int = 30) -> String {
        let recentEntries = entries.suffix(count)
        // Truncate each log to 150 chars max to keep payload small
        return recentEntries.map { entry in
            let display = entry.display
            return display.count > 150 ? String(display.prefix(150)) + "..." : display
        }.joined(separator: "\n")
    }
    
    /// Get session summary for bug reports
    func getSessionSummary() -> String {
        let errorCount = entries.filter { $0.level == .error }.count
        let warningCount = entries.filter { $0.level == .warning }.count
        let sessionDuration = entries.first.map { Date().timeIntervalSince($0.time) } ?? 0
        let minutes = Int(sessionDuration / 60)
        let seconds = Int(sessionDuration.truncatingRemainder(dividingBy: 60))
        
        return "Session: \(minutes)m \(seconds)s | Errors: \(errorCount) | Warnings: \(warningCount) | Total logs: \(entries.count)"
    }
    
    private func log(_ message: String, level: LogLevel, category: LogCategory) {
        let entry = LogEntry(time: Date(), level: level, category: category, message: message)
        
        // Store in memory
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        
        // OS log
        let osLog = loggers[category] ?? OSLog.default
        os_log("%{public}@", log: osLog, type: .default, entry.display)
        
        // File log - write to shared container for easy access
        writeToFile(entry.display)
        
        #if DEBUG
        print(entry.display)
        #endif
    }
    
    private func writeToFile(_ message: String) {
        Task.detached {
            let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("stokz_log.txt")
            let line = message + "\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: fileURL) {
                        try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: fileURL)
                }
            }
        }
    }
}

// MARK: - Global convenience

@MainActor
func logDebug(_ message: String, category: LogCategory = .app) {
    Logger.shared.debug(message, category: category)
}

@MainActor
func logInfo(_ message: String, category: LogCategory = .app) {
    Logger.shared.info(message, category: category)
}

@MainActor
func logWarning(_ message: String, category: LogCategory = .app) {
    Logger.shared.warning(message, category: category)
}

@MainActor
func logError(_ message: String, category: LogCategory = .app) {
    Logger.shared.error(message, category: category)
}

@MainActor
func logSuccess(_ message: String, category: LogCategory = .app) {
    Logger.shared.success(message, category: category)
}
