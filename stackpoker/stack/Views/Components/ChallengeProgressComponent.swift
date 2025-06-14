import SwiftUI

struct ChallengeProgressComponent: View {
    let challenge: Challenge
    let isCompact: Bool
    
    @State private var animatedProgress: Double = 0
    
    init(challenge: Challenge, isCompact: Bool = false) {
        self.challenge = challenge
        self.isCompact = isCompact
    }
    
    private var challengeTitle: String { challenge.title }
    private var challengeType: ChallengeType { challenge.type }
    private var currentValue: Double { challenge.currentValue }
    private var targetValue: Double { challenge.targetValue }
    private var progressPercentage: Double { challenge.progressPercentage }
    private var deadline: Date? { challenge.endDate }
    
    private var daysRemaining: Int? {
        guard let deadline = deadline else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: deadline).day
        return max(days ?? 0, 0)
    }
    
    private var isCompleted: Bool {
        return challenge.isCompleted
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
            // Header with enhanced styling
            HStack(spacing: 12) {
                // Enhanced icon with background
                ZStack {
                    Circle()
                        .fill(colorForType(challengeType).opacity(0.15))
                        .frame(width: isCompact ? 32 : 40, height: isCompact ? 32 : 40)
                    
                Image(systemName: challengeType.icon)
                        .font(.system(size: isCompact ? 16 : 20, weight: .semibold))
                    .foregroundColor(colorForType(challengeType))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                Text(challengeTitle)
                    .font(.plusJakarta(isCompact ? .callout : .headline, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    
                    // Enhanced status text
                    HStack(spacing: 6) {
                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("Completed")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        } else {
                            Text("\(challengeType.displayName) Challenge")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Spacer()
                
                // Enhanced percentage badge
                HStack(spacing: 4) {
                Text("\(Int(progressPercentage))%")
                        .font(.system(size: isCompact ? 14 : 16, weight: .bold))
                        .foregroundColor(isCompleted ? .white : colorForType(challengeType))
                    
                    if isCompleted {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.yellow)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isCompleted ? 
                              LinearGradient(colors: [.green, .green.opacity(0.8)], startPoint: .leading, endPoint: .trailing) :
                              LinearGradient(colors: [colorForType(challengeType).opacity(0.15), colorForType(challengeType).opacity(0.1)], startPoint: .leading, endPoint: .trailing)
                        )
                        .overlay(
                            Capsule()
                                .stroke(isCompleted ? .green.opacity(0.3) : colorForType(challengeType).opacity(0.3), lineWidth: 1)
                        )
                )
            }
            
            // Enhanced progress section
            VStack(alignment: .leading, spacing: 12) {
                // Values with better visual hierarchy - Updated for session challenges
                if challengeType == .session {
                    sessionChallengeValuesView
                } else {
                    standardChallengeValuesView
                }
                
                // Enhanced Progress Bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: isCompact ? 8 : 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
                            )
                        
                        // Progress fill with gradient
                        RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                            .fill(
                                LinearGradient(
                                    colors: isCompleted ? 
                                        [.green, .green.opacity(0.8), .green] :
                                        [colorForType(challengeType), colorForType(challengeType).opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * CGFloat(animatedProgress / 100), height: isCompact ? 8 : 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                                    .stroke(colorForType(challengeType).opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: colorForType(challengeType).opacity(0.3), radius: 2, y: 1)
                        
                        // Shimmer effect for completed challenges
                        if isCompleted {
                            RoundedRectangle(cornerRadius: isCompact ? 6 : 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.3), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * CGFloat(animatedProgress / 100), height: isCompact ? 8 : 12)
                                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: isCompleted)
                        }
                    }
                }
                .frame(height: isCompact ? 8 : 12)
            }
            
            // Deadline info with enhanced styling
            if let daysRemaining = daysRemaining, !isCompact {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    if daysRemaining > 0 {
                        Text("\(daysRemaining) days remaining")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.orange)
                    } else if daysRemaining == 0 {
                        Text("Due today!")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red)
                    } else {
                        Text("Overdue")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.1))
                        .overlay(
                            Capsule()
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding(isCompact ? 16 : 20)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 12 : 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.3),
                            Color.black.opacity(0.2),
                            colorForType(challengeType).opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 12 : 16)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    colorForType(challengeType).opacity(0.4),
                                    colorForType(challengeType).opacity(0.2),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: colorForType(challengeType).opacity(0.1), radius: 8, y: 4)
        )
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.8, blendDuration: 0.5)) {
                animatedProgress = isCompleted ? 100.0 : progressPercentage
            }
        }
        .onChange(of: progressPercentage) { newValue in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedProgress = isCompleted ? 100.0 : newValue
            }
        }
        .onChange(of: isCompleted) { newIsCompletedStatus in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                animatedProgress = newIsCompletedStatus ? 100.0 : progressPercentage
            }
        }
    }
    
    // Session challenge specific values view
    @ViewBuilder
    private var sessionChallengeValuesView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let targetCount = challenge.targetSessionCount {
                    Text("SESSIONS")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .tracking(1)
                    
                    Text("\(challenge.validSessionsCount)/\(targetCount)")
                        .font(.system(size: isCompact ? 18 : 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                } else {
                    Text("HOURS")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .tracking(1)
                    
                    Text("\(String(format: "%.1f", challenge.totalHoursPlayed))")
                        .font(.system(size: isCompact ? 18 : 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            
            Text("of")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .padding(.bottom, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                if let targetCount = challenge.targetSessionCount {
                    Text("TARGET")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .tracking(1)
                    
                    Text("\(targetCount)")
                        .font(.system(size: isCompact ? 16 : 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.gray.opacity(0.9))
                } else if let targetHours = challenge.targetHours {
                    Text("TARGET")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .tracking(1)
                    
                    Text("\(String(format: "%.1f", targetHours))h")
                        .font(.system(size: isCompact ? 16 : 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.gray.opacity(0.9))
                }
            }
            
            Spacer()
            
            // Remaining amount for session challenges
            if !isCompleted {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("REMAINING")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .tracking(1)
                    
                    if let targetCount = challenge.targetSessionCount {
                        let remaining = max(targetCount - challenge.validSessionsCount, 0)
                        Text("\(remaining)")
                            .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                            .foregroundColor(colorForType(challengeType))
                    } else if challenge.remainingHours > 0 {
                        Text("\(String(format: "%.1f", challenge.remainingHours))h")
                            .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                            .foregroundColor(colorForType(challengeType))
                    }
                }
            }
        }
        
        // Additional session info
        if let minHours = challenge.minHoursPerSession {
            Text("Minimum \(String(format: "%.1f", minHours))h per session")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .padding(.top, 4)
        }
        
        if challenge.currentSessionCount > 0 {
            Text("Average \(String(format: "%.1f", challenge.averageHoursPerSession))h per session")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .padding(.top, 2)
        }
    }
    
    // Standard challenge values view (for bankroll and hands)
    @ViewBuilder
    private var standardChallengeValuesView: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CURRENT")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.gray.opacity(0.8))
                    .tracking(1)
                
                Text(formattedValue.current)
                    .font(.system(size: isCompact ? 18 : 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text("of")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.gray)
                .padding(.bottom, 2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("TARGET")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.gray.opacity(0.8))
                    .tracking(1)
                
                Text(formattedValue.target)
                    .font(.system(size: isCompact ? 16 : 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.gray.opacity(0.9))
            }
            
            Spacer()
            
            // Remaining amount
            if !isCompleted {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("REMAINING")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                        .tracking(1)
                    
                    Text(formattedRemainingValue)
                        .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .rounded))
                        .foregroundColor(colorForType(challengeType))
                }
            }
        }
    }
    
    private var formattedRemainingValue: String {
        switch challengeType {
        case .bankroll:
            return "$\(Int(challenge.remainingValue).formattedWithCommas)"
        case .hands:
            return "\(Int(challenge.remainingValue))"
        case .session:
            return "\(Int(challenge.remainingValue))"
        }
    }
    
    private func colorForType(_ type: ChallengeType) -> Color {
        switch type {
        case .bankroll: return .green
        case .hands: return .purple
        case .session: return .orange
        }
    }
    
    private var formattedValue: (current: String, target: String) {
        switch challengeType {
        case .bankroll:
            return (
                current: "$\(Int(currentValue).formattedWithCommas)",
                target: "$\(Int(targetValue).formattedWithCommas)"
            )
        case .hands:
            return (
                current: "\(Int(currentValue))",
                target: "\(Int(targetValue))"
            )
        case .session:
            return (
                current: "\(Int(currentValue))",
                target: "\(Int(targetValue))"
            )
        }
    }
}

// Preview
struct ChallengeProgressComponent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ChallengeProgressComponent(
                challenge: Challenge(
                    userId: "preview",
                    type: .bankroll,
                    title: "Reach $20k Bankroll",
                    description: "Build bankroll to $20,000",
                    targetValue: 20000,
                    currentValue: 12500,
                    startingBankroll: 10000
                )
            )
            
            ChallengeProgressComponent(
                challenge: Challenge(
                    userId: "preview",
                    type: .session,
                    title: "Play 10 Long Sessions",
                    description: "Complete 10 sessions of at least 4 hours each",
                    targetValue: 10,
                    currentValue: 0,
                    targetSessionCount: 10,
                    minHoursPerSession: 4.0,
                    currentSessionCount: 6,
                    totalHoursPlayed: 28.5,
                    validSessionsCount: 6
                ),
                isCompact: true
            )
        }
        .padding()
        .background(Color.black)
    }
} 