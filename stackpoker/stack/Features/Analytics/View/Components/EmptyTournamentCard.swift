import SwiftUI

struct EmptyTournamentCard: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("🏆")
                .font(.system(size: 48))
            
            VStack(spacing: 8) {
                Text("No Tournaments Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Complete your first tournament to see analytics here.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .padding(.horizontal, 32)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(
            color: Color.black.opacity(0.3),
            radius: 20,
            x: 0,
            y: 8
        )
    }
}

#Preview {
    EmptyTournamentCard()
        .padding()
        .background(Color.black)
} 