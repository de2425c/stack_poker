import SwiftUI

struct SessionChallengeSetupView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var challengeService: ChallengeService
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var userService: UserService
    
    let userId: String
    
    // Challenge setup state
    @State private var challengeTitle = ""
    @State private var challengeDescription = ""
    @State private var isPublic = true
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    
    // Session challenge specific state
    @State private var challengeMode: SessionChallengeMode = .sessionCount
    @State private var targetSessionCount = "10"
    @State private var minHoursPerSession = "4.0"
    @State private var targetTotalHours = "40.0"
    
    // UI state
    @State private var isCreating = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // States for share prompt
    @State private var showShareChallengeSheet = false
    @State private var challengeToShare: Challenge?
    @State private var prefilledPostContent: String = ""
    // State for showing post editor after creating challenge
    @State private var showPostEditor: Bool = false
    
    enum SessionChallengeMode: String, CaseIterable {
        case sessionCount = "Session Count"
        case totalHours = "Total Hours"
        
        var description: String {
            switch self {
            case .sessionCount:
                return "Complete a specific number of qualifying sessions"
            case .totalHours:
                return "Accumulate a target number of total hours"
            }
        }
    }
    
    private var isFormValid: Bool {
        guard !challengeTitle.isEmpty else { return false }
        
        switch challengeMode {
        case .sessionCount:
            guard let sessionCount = Int(targetSessionCount), sessionCount > 0,
                  let minHours = Double(minHoursPerSession), minHours > 0 else {
                return false
            }
        case .totalHours:
            guard let totalHours = Double(targetTotalHours), totalHours > 0 else {
                return false
            }
        }
        
        return true
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                    .onTapGesture {
                        hideKeyboard()
                    }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Session Challenge")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Set goals for your poker sessions - track session count, hours played, and deadlines")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                                .lineLimit(nil)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Challenge Mode Selector
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Challenge Type")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            ForEach(SessionChallengeMode.allCases, id: \.self) { mode in
                                Button(action: {
                                    challengeMode = mode
                                }) {
                                    HStack(spacing: 16) {
                                        Image(systemName: challengeMode == mode ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 20))
                                            .foregroundColor(challengeMode == mode ? .orange : .gray)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(mode.rawValue)
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundColor(.white)
                                            
                                            Text(mode.description)
                                                .font(.system(size: 14))
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(challengeMode == mode ? Color.orange.opacity(0.15) : Color.black.opacity(0.25))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(challengeMode == mode ? Color.orange.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Basic Challenge Info
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Challenge Details")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            VStack(spacing: 12) {
                                ChallengeInputField(
                                    title: "Challenge Name",
                                    text: $challengeTitle,
                                    placeholder: "e.g., 'Play 10 Long Sessions'"
                                )
                                
                                ChallengeInputField(
                                    title: "Description (Optional)",
                                    text: $challengeDescription,
                                    placeholder: "Add details about your goal..."
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Session Challenge Parameters
                        if challengeMode == .sessionCount {
                            sessionCountChallengeSection
                        } else {
                            totalHoursChallengeSection
                        }
                        
                        // Deadline Section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Deadline")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Toggle("Set a deadline", isOn: $hasDeadline)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .toggleStyle(SwitchToggleStyle(tint: .orange))
                            
                            if hasDeadline {
                                DatePicker(
                                    "Target Date",
                                    selection: $deadline,
                                    in: Date()...,
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .colorScheme(.dark)
                                .padding(.vertical, 8)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Privacy Settings
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Privacy")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Toggle("Make this challenge public", isOn: $isPublic)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .toggleStyle(SwitchToggleStyle(tint: .orange))
                            
                            Text("Public challenges can be seen by other users and will appear in your profile")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .padding(.top, 4)
                        }
                        .padding(.horizontal, 20)
                        
                        // Create Button
                        Button(action: createChallenge) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .scaleEffect(0.8)
                                }
                                
                                Text(isCreating ? "Creating..." : "Create Challenge")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 27)
                                    .fill(isFormValid ? Color.orange : Color.gray.opacity(0.5))
                            )
                        }
                        .disabled(!isFormValid || isCreating)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onTapGesture {
                 hideKeyboard()
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onReceive(challengeService.$justCreatedChallenge) { newChallenge in
            if let newChallenge = newChallenge {
                self.challengeToShare = newChallenge
                self.showShareChallengeSheet = true
            }
        }
        .alert("Challenge Created!", isPresented: $showShareChallengeSheet) {
            Button("Share Challenge") {
                if let challenge = challengeToShare {
                    shareChallenge(challenge)
                }
                challengeService.justCreatedChallenge = nil
            }
            Button("Not Now", role: .cancel) { 
                challengeService.justCreatedChallenge = nil
                dismiss()
            }
        } message: {
            Text("Would you like to share that you started this challenge?")
        }
        .sheet(isPresented: $showPostEditor, onDismiss: {
            challengeService.justCreatedChallenge = nil
            dismiss()
        }) {
            if let challenge = challengeToShare {
                PostEditorView(
                    userId: userId,
                    prefilledContent: prefilledPostContent,
                    challengeToShare: challenge
                )
                .environmentObject(challengeService)
                .environmentObject(sessionStore)
                .environmentObject(postService)
                .environmentObject(userService)
            }
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private var sessionCountChallengeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Count Goal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                ChallengeInputField(
                    title: "Target Sessions",
                    text: $targetSessionCount,
                    placeholder: "10",
                    keyboardType: .numberPad
                )
                
                ChallengeInputField(
                    title: "Minimum Hours Per Session",
                    text: $minHoursPerSession,
                    placeholder: "4.0",
                    keyboardType: .decimalPad
                )
                
                if let sessionCount = Int(targetSessionCount),
                   let minHours = Double(minHoursPerSession),
                   sessionCount > 0 && minHours > 0 {
                    let totalHours = Double(sessionCount) * minHours
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenge Summary")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text("Complete \(sessionCount) sessions of at least \(String(format: "%.1f", minHours)) hours each")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("Total minimum hours: \(String(format: "%.1f", totalHours))")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var totalHoursChallengeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Total Hours Goal")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            VStack(spacing: 12) {
                ChallengeInputField(
                    title: "Target Total Hours",
                    text: $targetTotalHours,
                    placeholder: "40.0",
                    keyboardType: .decimalPad
                )
                
                if let totalHours = Double(targetTotalHours), totalHours > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenge Summary")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                        
                        Text("Accumulate \(String(format: "%.1f", totalHours)) total hours across all sessions")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                        
                        if hasDeadline {
                            let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
                            let hoursPerDay = totalHours / Double(max(days, 1))
                            
                            Text("Approximately \(String(format: "%.1f", hoursPerDay)) hours per day")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private func createChallenge() {
        guard isFormValid else { return }
        
        isCreating = true
        
        Task {
            do {
                let challenge: Challenge
                
                switch challengeMode {
                case .sessionCount:
                    guard let sessionCount = Int(targetSessionCount),
                          let minHours = Double(minHoursPerSession) else {
                        throw ChallengeError.invalidInput
                    }
                    
                    challenge = Challenge(
                        userId: userId,
                        type: .session,
                        title: challengeTitle,
                        description: challengeDescription.isEmpty ? "Complete \(sessionCount) sessions of at least \(String(format: "%.1f", minHours)) hours each" : challengeDescription,
                        targetValue: Double(sessionCount), // For display purposes
                        startDate: Date(),
                        endDate: hasDeadline ? deadline : nil,
                        isPublic: isPublic,
                        targetHours: Double(sessionCount) * minHours,
                        targetSessionCount: sessionCount,
                        minHoursPerSession: minHours
                    )
                    
                case .totalHours:
                    guard let totalHours = Double(targetTotalHours) else {
                        throw ChallengeError.invalidInput
                    }
                    
                    challenge = Challenge(
                        userId: userId,
                        type: .session,
                        title: challengeTitle,
                        description: challengeDescription.isEmpty ? "Accumulate \(String(format: "%.1f", totalHours)) total hours across all sessions" : challengeDescription,
                        targetValue: totalHours,
                        startDate: Date(),
                        endDate: hasDeadline ? deadline : nil,
                        isPublic: isPublic,
                        targetHours: totalHours
                    )
                }
                
                try await challengeService.createChallenge(challenge)
                
                await MainActor.run {
                    isCreating = false
                }
                
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
    
    private func shareChallenge(_ challenge: Challenge) {
        var challengeStartText = """
        🎯 Started a new challenge: \(challenge.title)
        
        Target: \(formattedValue(challenge.targetValue, type: challenge.type))
        Current: \(formattedValue(challenge.currentValue, type: challenge.type))
        """
        
        if challenge.type == .session {
            if let targetSessions = challenge.targetSessionCount, let minHours = challenge.minHoursPerSession {
                challengeStartText += "\nSessions: \(targetSessions) x \(String(format: "%.1f", minHours))h each"
            } else if let targetHours = challenge.targetHours {
                challengeStartText += "\nTotal Hours: \(String(format: "%.1f", targetHours))h"
            }
        }
        
        if let deadline = challenge.endDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            challengeStartText += "\nDeadline: \(formatter.string(from: deadline))"
        }
        
        challengeStartText += "\n\n#PokerChallenge #" + challenge.type.rawValue.capitalized + "Goal"
        
        prefilledPostContent = challengeStartText
        self.challengeToShare = challenge
        showPostEditor = true
    }

    private func formattedValue(_ value: Double, type: ChallengeType) -> String {
        switch type {
        case .bankroll:
            return "$\(Int(value).formattedWithCommas)"
        case .hands:
            return "\(Int(value))"
        case .session:
            if challengeMode == .sessionCount {
                return "\(Int(value)) sessions"
            } else {
                return "\(String(format: "%.1f", value)) hours"
            }
        }
    }
}

// MARK: - Supporting Views

struct ChallengeInputField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                )
        }
    }
}

// MARK: - Error Types

enum ChallengeError: LocalizedError {
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Please check your input values and try again."
        }
    }
}

#Preview {
    SessionChallengeSetupView(userId: "preview")
        .environmentObject(ChallengeService(userId: "preview"))
        .environmentObject(SessionStore(userId: "preview"))
} 
