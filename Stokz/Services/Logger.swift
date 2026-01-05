import Foundation
import os.log

/// Centralized logging for Stokz app
/// Uses Apple's unified logging system (os_log) for streaming via Console.app or log stream
enum LogCategory: String {
    case auth = "Auth"
    case sheets = "Sheets"
    case stocks = "Stocks"
    case portfolio = "Portfolio"
    case app = "App"
    case network = "Network"
    case ui = "UI"
}

enum LogLevel: String {
    case debug = "🔍"
    case info = "ℹ️"
    case warning = "⚠️"
    case error = "❌"
    case success = "✅"
}

final class Logger {
    static let shared = Logger()
    
    private let subsystem = "com.stokz.app"
    
    // Category-specific loggers
    private var loggers: [LogCategory: OSLog] = [:]
    
    private init() {
        // Initialize loggers for each category
        for category in [LogCategory.auth, .sheets, .stocks, .portfolio, .app, .network, .ui] {
            loggers[category] = OSLog(subsystem: subsystem, category: category.rawValue)
        }
    }
    
    // MARK: - Public Logging Methods
    
    func debug(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    func info(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    func error(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    func success(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .success, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Specialized Logging
    
    func networkRequest(_ method: String, url: String, category: LogCategory = .network) {
        info("📤 \(method) \(url)", category: category)
    }
    
    func networkResponse(_ statusCode: Int, url: String, duration: TimeInterval? = nil, category: LogCategory = .network) {
        let durationStr = duration.map { String(format: " (%.2fs)", $0) } ?? ""
        if (200..<300).contains(statusCode) {
            success("📥 \(statusCode) \(url)\(durationStr)", category: category)
        } else {
            error("📥 \(statusCode) \(url)\(durationStr)", category: category)
        }
    }
    
    func networkError(_ error: Error, url: String, category: LogCategory = .network) {
        self.error("📥 FAILED \(url): \(error.localizedDescription)", category: category)
    }
    
    // MARK: - Private
    
    private func log(_ message: String, level: LogLevel, category: LogCategory, file: String, function: String, line: Int) {
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.rawValue) [\(category.rawValue)] \(message) (\(fileName):\(line))"
        
        // Use os_log for system logging - use .fault level to ensure visibility
        let osLog = loggers[category] ?? OSLog.default
        
        // Always use .default or higher to ensure logs are captured
        os_log("%{public}@", log: osLog, type: .default, logMessage)
        
        // Always print to console (not just DEBUG)
        print(logMessage)
    }
}

// MARK: - Convenience Global Functions

func logDebug(_ message: String, category: LogCategory = .app) {
    Logger.shared.debug(message, category: category)
}

func logInfo(_ message: String, category: LogCategory = .app) {
    Logger.shared.info(message, category: category)
}

func logWarning(_ message: String, category: LogCategory = .app) {
    Logger.shared.warning(message, category: category)
}

func logError(_ message: String, category: LogCategory = .app) {
    Logger.shared.error(message, category: category)
}

func logSuccess(_ message: String, category: LogCategory = .app) {
    Logger.shared.success(message, category: category)
}
