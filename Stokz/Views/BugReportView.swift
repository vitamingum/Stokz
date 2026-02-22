import SwiftUI

/// Bug Report View - Multi-step form for submitting bug reports
struct BugReportView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var bugReportService = BugReportService.shared
    
    @State private var currentStep = 0
    @State private var bugTitle = ""
    @State private var bugDescription = ""
    @State private var severity: BugSeverity = .medium
    @State private var includeScreenshot = true
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    @Environment(\.dismiss) private var dismiss
    
    private let totalSteps = 4
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    progressBar
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Step content
                    TabView(selection: $currentStep) {
                        screenshotStep.tag(0)
                        titleStep.tag(1)
                        descriptionStep.tag(2)
                        severityStep.tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentStep)
                    
                    // Navigation buttons
                    navigationButtons
                        .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        bugReportService.reset()
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .principal) {
                    Text("REPORT BUG")
                        .font(.system(size: 16, weight: .black))
                        .tracking(2)
                        .foregroundColor(.white)
                }
            }
        }
        .alert("Bug Reported! 🎉", isPresented: $showSuccessAlert) {
            Button("OK") {
                bugReportService.reset()
                dismiss()
            }
        } message: {
            Text("Thanks for helping improve Stokz!")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Progress Bar
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.white : Color.gray.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }
    
    // MARK: - Step 1: Screenshot Preview
    private var screenshotStep: some View {
        VStack(spacing: 24) {
            Text("SCREENSHOT CAPTURED")
                .font(.system(size: 24, weight: .black))
                .tracking(2)
                .foregroundColor(.white)
            
            if let screenshot = bugReportService.capturedScreenshot {
                Image(uiImage: screenshot)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 200)
                    .overlay(
                        Text("No screenshot")
                            .foregroundColor(.gray)
                    )
            }
            
            Toggle(isOn: $includeScreenshot) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Include screenshot")
                }
                .foregroundColor(.white)
            }
            .toggleStyle(SwitchToggleStyle(tint: .white))
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Step 2: Bug Title
    private var titleStep: some View {
        VStack(spacing: 24) {
            Text("WHAT WENT WRONG?")
                .font(.system(size: 24, weight: .black))
                .tracking(2)
                .foregroundColor(.white)
            
            Text("Give your bug a short title")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            TextField("e.g., App crashes when adding stock", text: $bugTitle)
                .textFieldStyle(BugReportTextFieldStyle())
                .autocapitalization(.sentences)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Step 3: Description
    private var descriptionStep: some View {
        VStack(spacing: 24) {
            Text("DESCRIBE THE BUG")
                .font(.system(size: 24, weight: .black))
                .tracking(2)
                .foregroundColor(.white)
            
            Text("What were you doing when it happened?")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            TextEditor(text: $bugDescription)
                .frame(minHeight: 150)
                .padding(12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Step 4: Severity
    private var severityStep: some View {
        VStack(spacing: 24) {
            Text("HOW BAD IS IT?")
                .font(.system(size: 24, weight: .black))
                .tracking(2)
                .foregroundColor(.white)
            
            Text("Select the severity level")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            VStack(spacing: 12) {
                ForEach(BugSeverity.allCases, id: \.self) { level in
                    Button {
                        severity = level
                    } label: {
                        HStack {
                            Text(level.emoji)
                                .font(.title2)
                            
                            Text(level.rawValue.uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .tracking(1)
                            
                            Spacer()
                            
                            if severity == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .padding()
                        .background(severity == level ? Color.white.opacity(0.2) : Color.white.opacity(0.05))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(severity == level ? Color.white : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.white)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Navigation Buttons
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep > 0 {
                Button {
                    withAnimation {
                        currentStep -= 1
                    }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("BACK")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            
            if currentStep < totalSteps - 1 {
                Button {
                    withAnimation {
                        currentStep += 1
                    }
                } label: {
                    HStack {
                        Text("NEXT")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                }
                .disabled(currentStep == 1 && bugTitle.isEmpty)
                .opacity(currentStep == 1 && bugTitle.isEmpty ? 0.5 : 1)
            } else {
                Button {
                    submitBugReport()
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("SUBMIT")
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .tracking(1)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                }
                .disabled(isSubmitting || bugTitle.isEmpty)
                .opacity(isSubmitting || bugTitle.isEmpty ? 0.5 : 1)
            }
        }
    }
    
    // MARK: - Submit Bug Report
    private func submitBugReport() {
        guard let user = appState.authService.currentUser else {
            errorMessage = "You must be signed in to submit a bug report"
            showErrorAlert = true
            return
        }
        
        isSubmitting = true
        
        let screenshot = includeScreenshot ? bugReportService.capturedScreenshot : nil
        let report = BugReport(
            userId: user.id,
            userEmail: user.email,
            title: bugTitle,
            description: bugDescription,
            severity: severity,
            screenshot: screenshot,
            sessionSummary: Logger.shared.getSessionSummary(),
            recentLogs: Logger.shared.exportRecentLogs(count: 100)
        )
        
        Task {
            // 1. Always persist to disk first (works fully offline)
            await bugReportService.saveReportLocally(report)
            
            // 2. Try to upload immediately; if it fails the file stays on disk
            //    and will be retried on the next sign-in or foreground event.
            await bugReportService.uploadPendingReports(
                for: user.id,
                sheetsService: appState.sheetsService
            )
            
            isSubmitting = false
            showSuccessAlert = true
        }
    }
}

// MARK: - Custom Text Field Style
struct BugReportTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .foregroundColor(.white)
    }
}

#Preview {
    BugReportView()
        .environmentObject(AppState.shared)
}
