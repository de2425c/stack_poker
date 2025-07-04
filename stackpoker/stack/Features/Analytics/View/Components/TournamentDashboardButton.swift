import SwiftUI

struct TournamentDashboardButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Tournament icon
                Image(systemName: "trophy.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                // Title
                Text("Tournament Dashboard")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Arrow icon
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    // Beautiful purple gradient background
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.purple.opacity(0.8),
                            Color.indigo.opacity(0.6)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    
                    // Glossy highlight overlay for Whoop-style depth
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1),
                            Color.clear
                        ]),
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: Color.purple.opacity(0.4),
                radius: 12,
                x: 0,
                y: 6
            )
        }
        .buttonStyle(WhoopButtonStyle())
    }
}

#Preview {
    VStack {
        TournamentDashboardButton {
            print("Tournament Dashboard tapped")
        }
        .padding()
    }
    .background(Color.black)
} 