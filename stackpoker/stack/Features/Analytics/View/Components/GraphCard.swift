import SwiftUI

struct GraphCard<Content: View>: View {
    let title: String
    let subtitle: String
    let gradient: [Color]
    let content: Content
    
    init(title: String, subtitle: String, gradient: [Color], @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.gradient = gradient
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            // Graph content
            content
                .frame(maxHeight: .infinity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 0)
            
            // Bottom spacer
            Spacer()
                .frame(height: 20)
        }
        .frame(width: 380, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: gradient),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
    }
}