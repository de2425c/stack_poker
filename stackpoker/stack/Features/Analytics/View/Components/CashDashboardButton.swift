import SwiftUI

struct CashDashboardButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Cash icon
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                // Title
                Text("Cash Dashboard")
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
                    // Beautiful blue gradient background
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                            Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
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
                color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.4),
                radius: 12,
                x: 0,
                y: 6
            )
        }
        .buttonStyle(WhoopButtonStyle())
    }
}

struct WhoopButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

#Preview {
    VStack {
        CashDashboardButton {
            print("Cash Dashboard tapped")
        }
        .padding()
    }
    .background(Color.black)
} 