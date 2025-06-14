import SwiftUI

struct ChallengeDashboardView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var challengeService: ChallengeService
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var handStore: HandStore
    
    let userId: String
    
    @State private var showingBankrollSetup = false
    @State private var selectedChallenge: Challenge?
    @State private var showingChallengeDetail = false
    @State private var showingChallengeCompleted = false
    @State private var showingSessionSetup = false
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Challenges")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Set goals and track your poker journey")
                            .font(.system(size: 16))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    // Active Challenges Section
                    if challengeService.activeChallenges.isEmpty {
                        // No Active Challenges - Create First Challenge
                        VStack(spacing: 20) {
                            VStack(spacing: 12) {
                                Image(systemName: "target")
                                    .font(.system(size: 48, weight: .light))
                                    .foregroundColor(.gray.opacity(0.8))
                                
                                Text("No Active Challenges")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                Text("Create your first challenge to start tracking your poker goals")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 40)
                            
                            // Create Challenge Buttons
                            VStack(spacing: 12) {
                                // Bankroll Challenge Button
                                Button(action: { showingBankrollSetup = true }) {
                                    ChallengeTypeCard(
                                        icon: "dollarsign.circle.fill",
                                        title: "Bankroll Challenge",
                                        subtitle: "Set a bankroll target to reach",
                                        color: .green
                                    )
                                }
                                
                                // Session Challenge Button
                                Button(action: { showingSessionSetup = true }) {
                                    ChallengeTypeCard(
                                        icon: "clock.fill",
                                        title: "Session Challenge",
                                        subtitle: "Track sessions, hours, and deadlines",
                                        color: .orange
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    } else {
                        // Active Challenges
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Active Challenges")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Spacer()
                                
                                Menu {
                                    Button(action: { showingBankrollSetup = true }) {
                                        Label("Bankroll Challenge", systemImage: "dollarsign.circle.fill")
                                    }
                                    
                                    Button(action: { showingSessionSetup = true }) {
                                        Label("Session Challenge", systemImage: "clock.fill")
                                    }
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            ForEach(challengeService.activeChallenges) { challenge in
                                ChallengeProgressCard(challenge: challenge)
                                    .padding(.horizontal, 20)
                                    .onTapGesture {
                                        selectedChallenge = challenge
                                        if challenge.isCompleted {
                                            showingChallengeCompleted = true
                                        } else {
                                            showingChallengeDetail = true
                                        }
                                    }
                            }
                        }
                    }
                    
                    // Completed Challenges Section
                    if !challengeService.completedChallenges.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Recent Completions")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                            
                            ForEach(challengeService.completedChallenges.prefix(5)) { challenge in
                                CompletedChallengeCard(challenge: challenge)
                                    .padding(.horizontal, 20)
                                    .onTapGesture {
                                        selectedChallenge = challenge
                                        // Always show completed view for cards in this section
                                        showingChallengeCompleted = true 
                                    }
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    Spacer(minLength: 100) // Space for tab bar
                }
                .padding(.bottom, 20)
            }
        }
        .navigationBarHidden(false)
        .onAppear {
            // Update both bankroll and session challenges when view appears
            Task {
                await challengeService.updateBankrollFromSessions(sessionStore.sessions)
                
                // Update session challenges for all existing sessions
                for session in sessionStore.sessions {
                    await challengeService.updateSessionChallengesFromSession(session)
                }
            }
        }
        .onReceive(challengeService.$justCompletedChallenge) { completedChallenge in
            if let challenge = completedChallenge {
                // Show celebration after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    selectedChallenge = challenge
                    showingChallengeCompleted = true
                    // Clear the completed challenge to prevent showing again
                    challengeService.justCompletedChallenge = nil
                }
            }
        }
        .sheet(isPresented: $showingBankrollSetup) {
            BankrollChallengeSetupView(userId: userId)
                .environmentObject(challengeService)
                .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showingSessionSetup) {
            SessionChallengeSetupView(userId: userId)
                .environmentObject(challengeService)
                .environmentObject(sessionStore)
        }
        .sheet(isPresented: $showingChallengeDetail) {
            if let challenge = selectedChallenge {
                ChallengeDetailView(challenge: challenge, userId: userId)
                    .environmentObject(challengeService)
                    .environmentObject(sessionStore)
                    .environmentObject(userService)
                    .environmentObject(postService)
                    .environmentObject(handStore)
            }
        }
        .fullScreenCover(isPresented: $showingChallengeCompleted) {
            if let challenge = selectedChallenge {
                ChallengeCompletedView(challenge: challenge)
                    .environmentObject(challengeService)
                    .environmentObject(userService)
                    .environmentObject(postService)
            }
        }
    }
}

// MARK: - Challenge Progress Card
struct ChallengeProgressCard: View {
    let challenge: Challenge
    @EnvironmentObject private var challengeService: ChallengeService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: challenge.type.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(colorForType(challenge.type))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let daysRemaining = challenge.daysRemaining {
                        if daysRemaining > 0 {
                            Text("\(daysRemaining) days remaining")
                                .font(.system(size: 13))
                                .foregroundColor(.orange)
                        } else {
                            Text("Due today")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                    } else {
                        Text("No deadline")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                if challenge.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.green)
                }
            }
            
            // Progress Section - Updated for session challenges
            VStack(alignment: .leading, spacing: 8) {
                if challenge.type == .session {
                    // Session challenge specific display
                    sessionChallengeProgressView
                } else {
                    // Original display for other challenge types
                    standardChallengeProgressView
                }
                
                // Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorForType(challenge.type))
                            .frame(width: geometry.size.width * CGFloat(challenge.progressPercentage / 100), height: 8)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: challenge.progressPercentage)
                    }
                }
                .frame(height: 8)
            }
            
            // Remaining info
            if !challenge.isCompleted {
                if challenge.type == .session {
                    sessionChallengeRemainingView
                } else {
                    Text("\(formattedValue(challenge.remainingValue, type: challenge.type)) remaining")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(colorForType(challenge.type).opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // Session challenge specific progress view
    @ViewBuilder
    private var sessionChallengeProgressView: some View {
        if let targetCount = challenge.targetSessionCount {
            // Session count based challenge
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("\(challenge.validSessionsCount)/\(targetCount)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Hours")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("\(String(format: "%.1f", challenge.totalHoursPlayed))")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Progress")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("\(Int(challenge.progressPercentage))%")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colorForType(challenge.type))
                }
            }
            
            // Show minimum hours requirement if set
            if let minHours = challenge.minHoursPerSession {
                Text("Minimum \(String(format: "%.1f", minHours))h per session")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
            
        } else if let targetHours = challenge.targetHours {
            // Hours based challenge
            HStack {
                Text("\(String(format: "%.1f", challenge.totalHoursPlayed))h")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("/ \(String(format: "%.1f", targetHours))h")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Sessions")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("\(challenge.currentSessionCount)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Text("\(Int(challenge.progressPercentage))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(colorForType(challenge.type))
            }
            
            // Show average hours per session
            if challenge.currentSessionCount > 0 {
                Text("Average \(String(format: "%.1f", challenge.averageHoursPerSession))h per session")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.top, 4)
            }
        }
    }
    
    // Session challenge remaining view
    @ViewBuilder
    private var sessionChallengeRemainingView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let targetCount = challenge.targetSessionCount {
                let remainingSessions = max(targetCount - challenge.validSessionsCount, 0)
                if remainingSessions > 0 {
                    Text("\(remainingSessions) sessions remaining")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
            
            if challenge.remainingHours > 0 {
                Text("\(String(format: "%.1f", challenge.remainingHours)) hours remaining")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
        }
    }
    
    // Standard challenge progress view (for bankroll and hands)
    @ViewBuilder
    private var standardChallengeProgressView: some View {
        HStack {
            Text(formattedValue(challenge.currentValue, type: challenge.type))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Text("/ \(formattedValue(challenge.targetValue, type: challenge.type))")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.gray)
            
            Spacer()
            
            Text("\(Int(challenge.progressPercentage))%")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colorForType(challenge.type))
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
}

// MARK: - Completed Challenge Card
struct CompletedChallengeCard: View {
    let challenge: Challenge
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: challenge.type.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colorForType(challenge.type))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(challenge.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let completedAt = challenge.completedAt {
                    Text("Completed \(relativeDateFormatter(from: completedAt))")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func colorForType(_ type: ChallengeType) -> Color {
        switch type {
        case .bankroll: return .green
        case .hands: return .purple
        case .session: return .orange
        }
    }
    
    private func relativeDateFormatter(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Challenge Type Card
struct ChallengeTypeCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
} 