import SwiftUI
import UIKit

struct GlassMorphismTooltip: View {
    let title: String
    let message: String
    let step: Int
    let totalSteps: Int
    let showSkip: Bool
    let showButton: Bool
    let onNext: () -> Void
    let onSkip: () -> Void
    
    @State private var titleOpacity = 0.0
    @State private var messageOpacity = 0.0
    @State private var buttonOpacity = 0.0
    @State private var progressOpacity = 0.0
    @State private var glowAmount = 0.8
    
    private let glassGradient = LinearGradient(
        colors: [
            Color.white.opacity(0.25),
            Color.white.opacity(0.15),
            Color.white.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            // Compact progress indicator
            HStack(spacing: 4) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index < step ? Color.white : Color.white.opacity(0.3))
                        .frame(width: index < step ? 6 : 4, height: index < step ? 6 : 4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
                }
            }
            .opacity(progressOpacity)
            
            // Compact title
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(titleOpacity)
                    .multilineTextAlignment(.center)
            }
            
            // Compact message
            Text(message)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .lineSpacing(2)
                .opacity(messageOpacity)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            
            // Action buttons (only when needed)
            if showButton {
                HStack(spacing: 12) {
                    if showSkip {
                        Button(action: {
                            playHaptic()
                            onSkip()
                        }) {
                            Text("Skip")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    
                    Button(action: {
                        playHaptic()
                        onNext()
                    }) {
                        HStack(spacing: 6) {
                            Text(step == totalSteps ? "Done" : "Continue")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            
                            if step < totalSteps {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.white)
                                .overlay(
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white, Color.white.opacity(0.95)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .opacity(buttonOpacity)
            }
        }
        .padding(20)
        .background(
            ZStack {
                // Base blur effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                
                // Glass gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(glassGradient)
                
                // Glow effect
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.5),
                                Color.white.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
                    .blur(radius: 0.5)
                
                // Animated glow
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .blur(radius: 8)
                    .opacity(glowAmount)
            }
        )
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .shadow(color: .purple.opacity(0.1), radius: 20, x: 0, y: 10)
        .onAppear {
            animateIn()
            animateGlow()
        }
    }
    
    private func animateIn() {
        withAnimation(.easeOut(duration: 0.3)) {
            progressOpacity = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
            titleOpacity = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
            messageOpacity = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            buttonOpacity = 1.0
        }
    }
    
    private func animateGlow() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowAmount = 1.2
        }
    }
    
    private func playHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
}


