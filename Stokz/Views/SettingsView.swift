import SwiftUI

/// SettingsView - App settings with debug console
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var logger = Logger.shared
    @StateObject private var aiService = AIService.shared
    @State private var showDebugConsole = false
    @State private var apiKeyInput: String = ""
    @State private var isValidatingKey = false
    @State private var validationError: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Account Section  
                        accountSection
                        
                        // AI Section
                        aiSection
                        
                        // About Section
                        aboutSection
                        
                        // Debug Section
                        debugSection
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.system(size: 18, weight: .black))
                        .tracking(3)
                        .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showDebugConsole) {
                DebugConsoleView()
            }
            .onAppear {
                apiKeyInput = aiService.apiKey
            }
        }
    }
    
    // MARK: - Account Section
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("ACCOUNT", icon: "person.fill")
            
            if let user = appState.authService.currentUser {
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        UserAvatarView(user: user, size: 50)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName.uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text(user.email)
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.5))
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(white: 0.1))
                    .cornerRadius(8)
                    
                    Button(action: signOut) {
                        Text("SIGN OUT")
                            .font(.system(size: 12, weight: .black))
                            .tracking(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.15))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    // MARK: - AI Section
    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("AI PROVIDER", icon: "brain")
            
            VStack(spacing: 12) {
                // Provider picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("PROVIDER")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                    
                    HStack(spacing: 8) {
                        ForEach(LLMProvider.allCases, id: \.self) { provider in
                            Button(action: {
                                aiService.selectedProvider = provider
                                aiService.loadKeyForCurrentProvider()
                                apiKeyInput = aiService.apiKey
                            }) {
                                Text(provider.displayName)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(aiService.selectedProvider == provider ? Color.white : Color(white: 0.15))
                                    .foregroundColor(aiService.selectedProvider == provider ? .black : .white)
                                    .cornerRadius(6)
                            }
                        }
                    }
                }
                
                // API Key input
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("API KEY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                        Spacer()
                        if isValidatingKey {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if aiService.isConfigured {
                            if aiService.isKeyValid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 12))
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                        .font(.system(size: 12))
                                    Text("INVALID")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.yellow)
                                }
                            }
                        }
                    }
                    
                    HStack {
                        SecureField(aiService.selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if !apiKeyInput.isEmpty && apiKeyInput != aiService.apiKey {
                            Button(action: validateAndSaveKey) {
                                if isValidatingKey {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 40)
                                } else {
                                    Text("SAVE")
                                        .font(.system(size: 10, weight: .black))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.green)
                                        .foregroundColor(.black)
                                        .cornerRadius(4)
                                }
                            }
                            .disabled(isValidatingKey)
                        }
                    }
                    .padding()
                    .background(Color(white: 0.1))
                    .cornerRadius(8)
                    
                    // Show validation error
                    if let error = validationError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                    
                    // Show invalid key message if saved key is bad
                    if aiService.isConfigured && !aiService.isKeyValid && validationError == nil {
                        Text(aiService.validationMessage ?? "API key is invalid")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                    }
                }
                
                // Free tier toggle (rate limits requests)
                Toggle(isOn: $aiService.isFreeTier) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FREE TIER")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                        Text("Rate limit requests (15/min)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
                .tint(.green)
                
                // Get API key link
                Button(action: {
                    if let url = URL(string: aiService.selectedProvider.helpURL) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Text("Get \(aiService.selectedProvider.displayName) API Key")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color(white: 0.5))
                }
            }
            .padding()
            .background(Color(white: 0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - About Section
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("ABOUT", icon: "info.circle.fill")
            
            VStack(spacing: 12) {
                HStack {
                    Text("VERSION")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                HStack {
                    Text("BUILD")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color(white: 0.1))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Debug Section
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("DEBUG", icon: "terminal.fill")
            
            Button(action: { showDebugConsole = true }) {
                HStack {
                    Text("VIEW CONSOLE")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1)
                    Spacer()
                    Text("\(logger.entries.count) logs")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.4))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.3))
                }
                .foregroundColor(.white)
                .padding()
                .background(Color(white: 0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Helpers
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(title)
                .font(.system(size: 14, weight: .black))
                .tracking(2)
        }
        .foregroundColor(Color(white: 0.6))
    }
    
    private func loadSettings() {
        // No settings to load
    }
    
    private func signOut() {
        appState.signOut()
    }
    
    private func validateAndSaveKey() {
        isValidatingKey = true
        validationError = nil
        
        Task {
            let (valid, error) = await aiService.validateKey(apiKeyInput, for: aiService.selectedProvider)
            
            await MainActor.run {
                isValidatingKey = false
                
                if valid {
                    // Key is valid - save it
                    aiService.apiKey = apiKeyInput
                    aiService.isKeyValid = true
                    aiService.validationMessage = nil
                    validationError = nil
                } else {
                    validationError = error ?? "Invalid API key"
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState.shared)
}

// MARK: - Debug Console View
struct DebugConsoleView: View {
    @StateObject private var logger = Logger.shared
    @Environment(\.dismiss) var dismiss
    @State private var filter: LogCategory? = nil
    @State private var autoScroll = true
    
    private var filteredEntries: [LogEntry] {
        guard let filter = filter else { return logger.entries }
        return logger.entries.filter { $0.category == filter }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Filter bar
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "ALL", isSelected: filter == nil) {
                                filter = nil
                            }
                            ForEach([LogCategory.app, .auth, .sheets, .stocks, .portfolio, .network, .llm, .ui], id: \.rawValue) { cat in
                                FilterChip(title: cat.rawValue.uppercased(), isSelected: filter == cat) {
                                    filter = cat
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .background(Color(white: 0.05))
                    
                    // Log entries
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(filteredEntries) { entry in
                                    LogEntryRow(entry: entry)
                                        .id(entry.id)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        }
                        .onChange(of: logger.entries.count) { _, _ in
                            if autoScroll, let last = filteredEntries.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("DEBUG CONSOLE")
                        .font(.system(size: 14, weight: .black))
                        .tracking(2)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("DONE") { dismiss() }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { autoScroll.toggle() }) {
                            Label(autoScroll ? "Auto-scroll ON" : "Auto-scroll OFF",
                                  systemImage: autoScroll ? "checkmark" : "")
                        }
                        Button(role: .destructive, action: { logger.clear() }) {
                            Label("Clear Logs", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.white : Color(white: 0.15))
                .foregroundColor(isSelected ? .black : Color(white: 0.6))
                .cornerRadius(4)
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    
    var body: some View {
        Text(entry.display)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(levelColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }
    
    private var levelColor: Color {
        switch entry.level {
        case .error: return .red
        case .warning: return .orange
        case .success: return .green
        case .info: return Color(white: 0.7)
        case .debug: return Color(white: 0.5)
        }
    }
}
