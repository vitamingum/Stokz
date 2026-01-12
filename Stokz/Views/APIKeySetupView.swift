import SwiftUI

/// APIKeySetupView - Onboarding screen to set up AI provider after login
struct APIKeySetupView: View {
    @StateObject private var aiService = AIService.shared
    @State private var apiKeyInput: String = ""
    @State private var isValidating = false
    @State private var validationError: String?
    
    var onComplete: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "brain")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("SET UP AI")
                            .font(.system(size: 28, weight: .black))
                            .tracking(3)
                            .foregroundColor(.white)
                        
                        Text("Add an API key to enable AI-powered stock analysis and smack talk")
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 60)
                    
                    // Provider Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CHOOSE PROVIDER")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Color(white: 0.5))
                        
                        VStack(spacing: 8) {
                            ForEach(LLMProvider.allCases, id: \.self) { provider in
                                Button(action: {
                                    aiService.selectedProvider = provider
                                    aiService.loadKeyForCurrentProvider()
                                    apiKeyInput = aiService.apiKey
                                }) {
                                    HStack {
                                        Text(provider.displayName)
                                            .font(.system(size: 16, weight: .bold))
                                        
                                        Spacer()
                                        
                                        if provider == .gemini {
                                            Text("FREE")
                                                .font(.system(size: 10, weight: .black))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.green)
                                                .foregroundColor(.black)
                                                .cornerRadius(4)
                                        }
                                        
                                        if aiService.selectedProvider == provider {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                    }
                                    .padding()
                                    .background(aiService.selectedProvider == provider ? Color(white: 0.2) : Color(white: 0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // API Key Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ENTER API KEY")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Color(white: 0.5))
                        
                        SecureField(aiService.selectedProvider.apiKeyPlaceholder, text: $apiKeyInput)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(white: 0.1))
                            .cornerRadius(8)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        if let error = validationError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                        
                        // Get API key link
                        Button(action: {
                            if let url = URL(string: aiService.selectedProvider.helpURL) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.right.circle")
                                Text("Get a free \(aiService.selectedProvider.displayName) API key")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 40)
                    
                    // Continue Button
                    VStack(spacing: 12) {
                        Button(action: saveAndContinue) {
                            HStack {
                                if isValidating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                } else {
                                    Text("CONTINUE")
                                        .font(.system(size: 16, weight: .black))
                                        .tracking(2)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(apiKeyInput.isEmpty ? Color(white: 0.3) : Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        }
                        .disabled(apiKeyInput.isEmpty || isValidating)
                        
                        Button(action: onComplete) {
                            Text("Skip for now")
                                .font(.system(size: 14))
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    private func saveAndContinue() {
        isValidating = true
        validationError = nil
        
        // Save the key
        aiService.apiKey = apiKeyInput
        
        // Simple validation - just check it's not empty
        // A real validation would test the API
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // Brief delay for UX
            await MainActor.run {
                isValidating = false
                onComplete()
            }
        }
    }
}
