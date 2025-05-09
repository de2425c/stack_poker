import SwiftUI

struct SessionBadgeView: View {
    let gameName: String
    let stakes: String
    
    var body: some View {
        HStack(spacing: 6) {
            // Game controller icon
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
            
            // Session info text
            Text("\(gameName) (\(stakes))")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 1)
        )
    }
}

#Preview {
    SessionBadgeView(gameName: "Wynn", stakes: "$2/$5/$10")
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.black)
} 
