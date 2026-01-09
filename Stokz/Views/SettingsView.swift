import SwiftUI

/// SettingsView - App settings with debug console
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var logger = Logger.shared
    @StateObject private var llmService = LocalLLMService.shared
    @State private var showDebugConsole = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Account Section  
                        accountSection
                        
                        // LLM Section
                        llmSection
                        
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
    
    // MARK: - LLM Section
    private var llmSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("LOCAL AI", icon: "brain")
            
            VStack(spacing: 12) {
                // Status message
                HStack {
                    Text("STATUS")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                    Spacer()
                    Text(llmService.statusMessage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(llmService.isModelLoaded ? .green : (llmService.isDownloading || llmService.isLoadingModel ? .yellow : Color(white: 0.4)))
                }
                
                // Download progress
                if llmService.isDownloading {
                    VStack(spacing: 8) {
                        ProgressView(value: llmService.downloadProgress)
                            .progressViewStyle(.linear)
                            .tint(.green)
                        Text("\(Int(llmService.downloadProgress * 100))% downloaded")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
                
                // Loading indicator
                if llmService.isLoadingModel {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.7)
                        Text("Loading model into memory...")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.5))
                    }
                }
                
                // Model size info
                HStack {
                    Text("MODEL SIZE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.5))
                    Spacer()
                    Text(llmService.modelSizeString)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                }
                
                // Error message
                if let error = llmService.lastError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
