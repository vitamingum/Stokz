import Foundation
import AuthenticationServices
import CryptoKit

/// AuthenticationService handles Google OAuth authentication
/// Uses ASWebAuthenticationSession for secure OAuth flow
@MainActor
class AuthenticationService: NSObject, ObservableObject {
    
    static let shared = AuthenticationService()
    
    // MARK: - Configuration
    /// Google OAuth credentials from Google Cloud Console
    private let clientId = "195954547830-g5omt5r1p6s7li3l28e04oe8jsd315c7.apps.googleusercontent.com"
    private let redirectURI = "com.googleusercontent.apps.195954547830-g5omt5r1p6s7li3l28e04oe8jsd315c7:/oauth2redirect"
    
    // OAuth endpoints
    private let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let userInfoEndpoint = "https://www.googleapis.com/oauth2/v3/userinfo"
    
    // Scopes needed for Google Sheets access
    // Using spreadsheets scope - allows access to any Google Sheet
    // drive.file was too restrictive and didn't work for shared sheets
    private let scopes = [
        "openid",
        "profile",
        "email",
        "https://www.googleapis.com/auth/spreadsheets"
    ]
    
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var error: String?
    
    private var accessToken: String?
    private var refreshToken: String?
    private var codeVerifier: String?
    
    // MARK: - Sign In
    func signIn() async {
        logInfo("Starting OAuth sign-in flow", category: .auth)
        isLoading = true
        error = nil
        
        // Generate PKCE code verifier and challenge
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier!)
        logDebug("Generated PKCE challenge", category: .auth)
        
        // Build authorization URL
        var components = URLComponents(string: authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = components.url else {
            logError("Failed to create authorization URL", category: .auth)
            error = "Failed to create authorization URL"
            isLoading = false
            return
        }
        
        logInfo("Opening OAuth web session", category: .auth)
        // Use real OAuth authentication
        await performWebAuthentication(url: authURL)
    }
    
    // MARK: - Web Authentication
    private func performWebAuthentication(url: URL) async {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: "com.googleusercontent.apps.195954547830-g5omt5r1p6s7li3l28e04oe8jsd315c7"
            ) { [weak self] callbackURL, error in
                guard let self = self else { 
                    continuation.resume()
                    return 
                }
                
                if let error = error {
                    Task { @MainActor in
                        logError("OAuth web auth failed: \(error.localizedDescription)", category: .auth)
                        self.error = error.localizedDescription
                        self.isLoading = false
                    }
                    continuation.resume()
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let code = self.extractCode(from: callbackURL) else {
                    Task { @MainActor in
                        logError("Failed to extract authorization code from callback", category: .auth)
                        self.error = "Failed to get authorization code"
                        self.isLoading = false
                    }
                    continuation.resume()
                    return
                }
                
                logSuccess("Got authorization code, exchanging for token", category: .auth)
                Task {
                    await self.exchangeCodeForToken(code: code)
                    continuation.resume()
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            
            if !session.start() {
                Task { @MainActor in
                    logError("Failed to start ASWebAuthenticationSession", category: .auth)
                    self.error = "Failed to start authentication session"
                    self.isLoading = false
                }
                continuation.resume()
            }
        }
    }
    
    // MARK: - Exchange Code for Token
    private func exchangeCodeForToken(code: String) async {
        logInfo("Exchanging authorization code for tokens", category: .auth)
        guard let codeVerifier = codeVerifier else {
            logError("Missing PKCE code verifier", category: .auth)
            error = "Missing code verifier"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        Logger.shared.networkRequest("POST", url: tokenEndpoint, category: .auth)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            Logger.shared.networkResponse(httpResponse?.statusCode ?? 0, url: tokenEndpoint, category: .auth)
            
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            
            accessToken = tokenResponse.accessToken
            refreshToken = tokenResponse.refreshToken
            logSuccess("Got access token (refresh: \(refreshToken != nil ? "yes" : "no"))", category: .auth)
            
            // Save credentials for persistence
            saveCredentials()
            
            // Fetch user info
            await fetchUserInfo()
            
            // Set token in Google Sheets service
            GoogleSheetsService.shared.setAccessToken(accessToken!)
            
            // Save user to Google Sheets
            if let user = currentUser {
                logInfo("Saving user to Google Sheets: \(user.displayName)", category: .auth)
                do {
                    try await GoogleSheetsService.shared.saveUser(user)
                    logSuccess("User saved to Sheets", category: .auth)
                } catch {
                    logError("Failed to save user to Sheets: \(error.localizedDescription)", category: .auth)
                }
            }
            
            isAuthenticated = true
            logSuccess("Sign-in complete! User: \(currentUser?.displayName ?? "unknown")", category: .auth)
        } catch {
            logError("Token exchange failed: \(error.localizedDescription)", category: .auth)
            self.error = "Failed to exchange code for token: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Fetch User Info
    func fetchUserInfo() async {
        guard let token = accessToken else {
            logError("No access token for user info fetch", category: .auth)
            return
        }
        
        var request = URLRequest(url: URL(string: userInfoEndpoint)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        Logger.shared.networkRequest("GET", url: userInfoEndpoint, category: .auth)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            Logger.shared.networkResponse(httpResponse?.statusCode ?? 0, url: userInfoEndpoint, category: .auth)
            
            let userInfo = try JSONDecoder().decode(GoogleUserInfo.self, from: data)
            
            currentUser = User(
                id: userInfo.sub,
                email: userInfo.email,
                displayName: userInfo.name ?? userInfo.email,
                photoURL: userInfo.picture,
                createdAt: Date()
            )
            logSuccess("Fetched user info: \(userInfo.email)", category: .auth)
        } catch {
            logError("Failed to fetch user info: \(error.localizedDescription)", category: .auth)
            self.error = "Failed to fetch user info: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Sign Out
    func signOut() {
        logInfo("Signing out user: \(currentUser?.displayName ?? "unknown")", category: .auth)
        currentUser = nil
        accessToken = nil
        refreshToken = nil
        isAuthenticated = false
        
        // Clear stored credentials
        UserDefaults.standard.removeObject(forKey: "accessToken")
        UserDefaults.standard.removeObject(forKey: "refreshToken")
        logSuccess("Sign-out complete", category: .auth)
    }
    
    // MARK: - Refresh Token
    func refreshAccessToken() async throws {
        logInfo("Refreshing access token", category: .auth)
        guard let refreshToken = refreshToken else {
            logError("No refresh token available", category: .auth)
            throw AuthError.notAuthenticated
        }
        
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = body
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        Logger.shared.networkRequest("POST", url: "\(tokenEndpoint) (refresh)", category: .auth)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as? HTTPURLResponse
        Logger.shared.networkResponse(httpResponse?.statusCode ?? 0, url: "\(tokenEndpoint) (refresh)", category: .auth)
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        accessToken = tokenResponse.accessToken
        GoogleSheetsService.shared.setAccessToken(accessToken!)
        saveCredentials()
        logSuccess("Token refreshed successfully", category: .auth)
    }
    
    // MARK: - PKCE Helpers
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func extractCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        return code
    }
    
    // MARK: - Persistence
    func saveCredentials() {
        UserDefaults.standard.set(accessToken, forKey: "accessToken")
        UserDefaults.standard.set(refreshToken, forKey: "refreshToken")
    }
    
    func loadCredentials() {
        accessToken = UserDefaults.standard.string(forKey: "accessToken")
        refreshToken = UserDefaults.standard.string(forKey: "refreshToken")
        
        if accessToken != nil {
            GoogleSheetsService.shared.setAccessToken(accessToken!)
        }
    }
    
    // MARK: - Get Access Token
    func getAccessToken() -> String? {
        return accessToken
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension AuthenticationService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

// MARK: - Response Models
struct TokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

struct GoogleUserInfo: Codable {
    let sub: String
    let email: String
    let name: String?
    let picture: String?
    let emailVerified: Bool?
    
    enum CodingKeys: String, CodingKey {
        case sub
        case email
        case name
        case picture
        case emailVerified = "email_verified"
    }
}

// MARK: - Errors
enum AuthError: Error, LocalizedError {
    case notAuthenticated
    case tokenExpired
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .tokenExpired:
            return "Session expired. Please sign in again."
        case .invalidResponse:
            return "Invalid authentication response"
        }
    }
}
