import SwiftUI

struct ChallengeProgressComponent: View {
    let challengeTitle: String
    let challengeType: ChallengeType
    let currentValue: Double
    let targetValue: Double
    let progressPercentage: Double
    let isCompact: Bool
    let deadline: Date?
    
    init(challengeTitle: String, challengeType: ChallengeType, currentValue: Double, targetValue: Double, isCompact: Bool = false, deadline: Date? = nil) {
        self.challengeTitle = challengeTitle
        self.challengeType = challengeType
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.progressPercentage = min(max(currentValue / targetValue * 100, 0), 100)
        self.isCompact = isCompact
        self.deadline = deadline
    }
    
    private var daysRemaining: Int? {
        guard let deadline = deadline else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: deadline).day
        return max(days ?? 0, 0)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: challengeType.icon)
                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                    .foregroundColor(colorForType(challengeType))
                
                Text(challengeTitle)
                    .font(.plusJakarta(isCompact ? .callout : .headline, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(Int(progressPercentage))%")
                    .font(.system(size: isCompact ? 12 : 14, weight: .medium))
                    .foregroundColor(colorForType(challengeType))
            }
            
            // Deadline info
            if let daysRemaining = daysRemaining, !isCompact {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                    
                    if daysRemaining > 0 {
                        Text("\(daysRemaining) days left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.orange)
                    } else if daysRemaining == 0 {
                        Text("Due today!")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    } else {
                        Text("Overdue")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Progress values
            if !isCompact {
                HStack {
                    Text(formattedValue(currentValue, type: challengeType))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("/ \(formattedValue(targetValue, type: challengeType))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: isCompact ? 4 : 6)
                    
                    RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                        .fill(colorForType(challengeType))
                        .frame(width: geometry.size.width * CGFloat(progressPercentage / 100), height: isCompact ? 4 : 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progressPercentage)
                }
            }
            .frame(height: isCompact ? 4 : 6)
            
            // Compact values display
            if isCompact {
                Text("\(formattedValue(currentValue, type: challengeType)) / \(formattedValue(targetValue, type: challengeType))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
        .padding(isCompact ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 8 : 12)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: isCompact ? 8 : 12)
                        .stroke(colorForType(challengeType).opacity(0.3), lineWidth: 1)
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

// Preview
struct ChallengeProgressComponent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ChallengeProgressComponent(
                challengeTitle: "Reach $20k Bankroll",
                challengeType: .bankroll,
                currentValue: 12500,
                targetValue: 20000
            )
            
            ChallengeProgressComponent(
                challengeTitle: "Reach $20k Bankroll",
                challengeType: .bankroll,
                currentValue: 12500,
                targetValue: 20000,
                isCompact: true
            )
        }
        .padding()
        .background(Color.black)
    }
} 