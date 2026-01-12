import SwiftUI
import UIKit

/// BugReport model for storing bug report data
struct BugReport: Codable {
    let id: String
    let userId: String
    let userEmail: String
    let title: String
    let description: String
    let severity: BugSeverity
    let screenshotData: String? // Base64 encoded image
    let deviceInfo: String
    let appVersion: String
    let sessionSummary: String
    let recentLogs: String
    let timestamp: Date
    
    init(
        userId: String,
        userEmail: String,
        title: String,
        description: String,
        severity: BugSeverity,
        screenshot: UIImage?,
        sessionSummary: String,
        recentLogs: String
    ) {
        self.id = UUID().uuidString
        self.userId = userId
        self.userEmail = userEmail
        self.title = title
        self.description = description
        self.severity = severity
        // Compress screenshot heavily and resize to fit in Google Sheets cell limit (50k chars)
        self.screenshotData = BugReport.compressScreenshot(screenshot)
        self.deviceInfo = BugReport.getDeviceInfo()
        self.appVersion = BugReport.getAppVersion()
        self.sessionSummary = sessionSummary
        // Truncate logs to fit in cell limit
        self.recentLogs = String(recentLogs.prefix(40000))
        self.timestamp = Date()
    }
    
    private static func compressScreenshot(_ image: UIImage?) -> String? {
        guard let image = image else { return nil }
        // Resize to max 400px wide to reduce size
        let maxWidth: CGFloat = 400
        let scale = min(maxWidth / image.size.width, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Compress to JPEG with low quality
        return resized?.jpegData(compressionQuality: 0.3)?.base64EncodedString()
    }
    
    private static func getDeviceInfo() -> String {
        let device = UIDevice.current
        return "\(device.model) - iOS \(device.systemVersion)"
    }
    
    static func getDeviceInfoStatic() -> String {
        let device = UIDevice.current
        return "\(device.model) - iOS \(device.systemVersion)"
    }
    
    private static func getAppVersion() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
    
    static func getAppVersionStatic() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }
}

enum BugSeverity: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
    
    var emoji: String {
        switch self {
        case .low: return "🟢"
        case .medium: return "🟡"
        case .high: return "🟠"
        case .critical: return "🔴"
        }
    }
}

/// BugReportService handles screenshot capture and shake detection
@MainActor
class BugReportService: ObservableObject {
    static let shared = BugReportService()
    
    @Published var isShowingBugReport = false
    @Published var capturedScreenshot: UIImage?
    
    private init() {}
    
    /// Capture the current screen
    func captureScreen() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { context in
            window.layer.render(in: context.cgContext)
        }
    }
    
    /// Trigger bug report flow
    func triggerBugReport() {
        logInfo("📸 Bug report triggered - capturing screen", category: .app)
        capturedScreenshot = captureScreen()
        isShowingBugReport = true
    }
    
    /// Reset the bug report state
    func reset() {
        capturedScreenshot = nil
        isShowingBugReport = false
    }
}

// MARK: - Shake Gesture Detection
/// UIWindow extension to detect shake gestures
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

/// SwiftUI modifier to handle shake gestures
struct ShakeDetector: ViewModifier {
    let onShake: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                onShake()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(onShake: action))
    }
}
