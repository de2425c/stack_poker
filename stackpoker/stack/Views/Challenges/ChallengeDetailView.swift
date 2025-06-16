import SwiftUI

struct ChallengeDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var challengeService: ChallengeService
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var handStore: HandStore
    
    @Binding var challenge: Challenge
    let userId: String
    
    @State private var showingUpdatePost = false
    @State private var showingAbandonAlert = false
    @State private var isAbandoningChallenge = false
    
    // MARK: - Computed Properties
    
    private var progressSectionBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.black.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colorForType(challenge.type).opacity(0.3), lineWidth: 1)
            )
    }
    
    private var abandonButtonBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.red.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
            )
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: challenge.type.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(colorForType(challenge.type))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(challenge.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    
                    if !challenge.description.isEmpty {
                        Text(challenge.description)
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
            }
            
            // Status Badge
            HStack {
                ChallengeStatusBadge(status: challenge.status)
                
                Spacer()
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Large Progress Display
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Progress")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Text(formattedValue(displayCurrentValue, type: challenge.type))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Target")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Text(formattedValue(challenge.targetValue, type: challenge.type))
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                
                // Progress Percentage
                HStack {
                    Text("\(Int(displayProgress))% Complete")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(colorForType(challenge.type))
                    
                    Spacer()
                    
                    if !challenge.isCompleted {
                        Text("\(formattedValue(displayRemainingValue, type: challenge.type)) remaining")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                // Progress Bar
                ProgressView(value: displayProgress / 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: colorForType(challenge.type)))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
            }
            .padding(20)
            .background(progressSectionBackground)
        }
        .padding(.horizontal, 20)
    }
    
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                DetailRow(
                    icon: "calendar",
                    title: "Created",
                    value: formatDate(challenge.createdAt)
                )
                
                if let endDate = challenge.endDate {
                    DetailRow(
                        icon: "clock",
                        title: "Deadline",
                        value: formatDate(endDate),
                        isDeadline: true,
                        daysRemaining: challenge.daysRemaining
                    )
                }
                
                if let completedAt = challenge.completedAt {
                    DetailRow(
                        icon: "checkmark.circle",
                        title: "Completed",
                        value: formatDate(completedAt)
                    )
                }
                
                DetailRow(
                    icon: challenge.isPublic ? "globe" : "lock",
                    title: "Visibility",
                    value: challenge.isPublic ? "Public" : "Private"
                )
                
                // Bankroll specific details
                if challenge.type == .bankroll,
                   let startingBankroll = challenge.startingBankroll {
                    DetailRow(
                        icon: "dollarsign.circle",
                        title: "Starting Bankroll",
                        value: formattedValue(startingBankroll, type: .bankroll)
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: { showingUpdatePost = true }) {
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Post Update")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorForType(challenge.type))
                )
            }
            
            Button(action: { showingAbandonAlert = true }) {
                HStack {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("Abandon Challenge")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(abandonButtonBackground)
            }
        }
        .padding(.horizontal, 20)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        progressSection
                        detailsSection
                        
                        if challenge.status == .active {
                            actionButtonsSection
                        }
                        
                        Spacer(minLength: 50)
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .alert("Abandon Challenge", isPresented: $showingAbandonAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Abandon", role: .destructive) {
                abandonChallenge()
            }
        } message: {
            Text("Are you sure you want to abandon this challenge? This action cannot be undone.")
        }
        .sheet(isPresented: $showingUpdatePost) {
            PostEditorView(
                userId: userId,
                challengeToShare: challenge,
                isChallengeUpdate: true
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .environmentObject(handStore)
            .environmentObject(sessionStore)
        }
    }
    
    private func abandonChallenge() {
        guard let challengeId = challenge.id else {
            print("❌ Cannot abandon challenge: missing ID")
            return
        }
        
        isAbandoningChallenge = true
        Task {
            do {
                try await challengeService.abandonChallenge(challengeId: challengeId)
                await MainActor.run {
                    isAbandoningChallenge = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isAbandoningChallenge = false
                    print("❌ Error abandoning challenge: \(error)")
                }
            }
        }
    }
    
    private func colorForType(_ type: ChallengeType) -> Color {
        switch type {
        case .bankroll: return .green
        case .hands: return .purple
        case .session: return .orange
        }
    }
    
    private func formattedValue(_ value: Double, type: ChallengeType) -> String {
        switch type {
        case .bankroll:
            return "$\(Int(value).formattedWithCommas)"
        case .hands:
            return "\(Int(value))"
        case .session:
            return "\(Int(value))"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func generateChallengeUpdateText(for challenge: Challenge) -> String {
        // Dynamically determine current progress value, especially for session challenges
        var current: Double = challenge.currentValue
        if challenge.type == .session {
            if let _ = challenge.targetHours {
                current = challenge.totalHoursPlayed
            } else if let _ = challenge.targetSessionCount {
                current = Double(challenge.validSessionsCount)
            }
        }
        
        var updateText = """
        🎯 Challenge Update: \(challenge.title)
        
        Progress: \(formattedValue(current, type: challenge.type))
        Target: \(formattedValue(challenge.targetValue, type: challenge.type))
        
        \(Int(challenge.progressPercentage))% Complete
        """
        
        if let deadline = challenge.endDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            updateText += "\nDeadline: \(formatter.string(from: deadline))"
        }
        
        updateText += "\n\n#ChallengeProgress #\(challenge.type.rawValue.capitalized)Goal"
        
        return updateText
    }
    
    private var displayCurrentValue: Double {
        if challenge.isCompleted {
            return challenge.targetValue
        }
        if challenge.type == .session {
            if challenge.targetSessionCount != nil {
                return Double(challenge.validSessionsCount)
            } else if challenge.targetHours != nil {
                return challenge.totalHoursPlayed
            }
        }
        return challenge.currentValue
    }
    
    private var displayProgress: Double {
        challenge.isCompleted ? 100 : challenge.progressPercentage
    }
    
    private var displayRemainingValue: Double {
        if challenge.isCompleted { return 0 }
        return challenge.remainingValue
    }
}

// MARK: - Supporting Views
struct ChallengeStatusBadge: View {
    let status: ChallengeStatus
    
    private var badgeBackground: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(colorForStatus(status).opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(colorForStatus(status).opacity(0.3), lineWidth: 1)
            )
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconForStatus(status))
                .font(.system(size: 12, weight: .semibold))
            
            Text(status.displayName)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(colorForStatus(status))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(badgeBackground)
    }
    
    private func colorForStatus(_ status: ChallengeStatus) -> Color {
        switch status {
        case .active: return .green
        case .completed: return .blue
        case .failed: return .red
        case .abandoned: return .orange
        }
    }
    
    private func iconForStatus(_ status: ChallengeStatus) -> String {
        switch status {
        case .active: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .abandoned: return "pause.circle.fill"
        }
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    var isDeadline: Bool = false
    var daysRemaining: Int? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                if isDeadline, let days = daysRemaining {
                    if days > 0 {
                        Text("\(days) days left")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    } else if days == 0 {
                        Text("Due today")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    } else {
                        Text("Overdue")
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
} 