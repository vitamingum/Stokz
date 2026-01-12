import SwiftUI

/// APIKeySetupView - Onboarding screen to set up Gemini API key after Google sign-in
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
                        
                        Text("ONE MORE THING")
                            .font(.system(size: 28, weight: .black))
                            .tracking(3)
                            .foregroundColor(.white)
                        
                        Text("Add your free Gemini API key to enable AI-powered smack talk")
                            .font(.system(size: 14))
                            .foregroundColor(Color(white: 0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 60)
                    
                    // API Key Input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GEMINI API KEY")
                            .font(.system(size: 12, weight: .bold))
                            .tracking(1)
                            .foregroundColor(Color(white: 0.5))
                        
                        SecureField("AIza...", text: $apiKeyInput)
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
                            if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.right.circle")
                                Text("Get a free Gemini API key")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                        }
                        
                        Text("Uses same Google account you just signed in with")
                            .font(.system(size: 12))
                            .foregroundColor(Color(white: 0.4))
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
        
        // Set provider to Gemini and save key
        aiService.selectedProvider = .gemini
        aiService.apiKey = apiKeyInput
        
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            await MainActor.run {
                isValidating = false
                onComplete()
            }
        }
    }
}
