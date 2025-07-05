import SwiftUI

struct PulsingHighlight: ViewModifier {
    let isActive: Bool
    let color: Color
    
    @State private var pulseAnimation = false
    @State private var glowAnimation = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if isActive {
                        // Pulsing border
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color, lineWidth: 3)
                            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
                            .opacity(pulseAnimation ? 0.6 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )
                        
                        // Glowing effect
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color, lineWidth: 2)
                            .blur(radius: glowAnimation ? 15 : 8)
                            .opacity(glowAnimation ? 0.8 : 0.4)
                            .animation(
                                .easeInOut(duration: 1.2)
                                .repeatForever(autoreverses: true),
                                value: glowAnimation
                            )
                    }
                }
            )
            .scaleEffect(isActive ? 1.02 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
            .onAppear {
                if isActive {
                    DispatchQueue.main.async {
                        pulseAnimation = true
                        glowAnimation = true
                    }
                }
            }
            .onChange(of: isActive) { newValue in
                if newValue {
                    DispatchQueue.main.async {
                        pulseAnimation = true
                        glowAnimation = true
                    }
                } else {
                    pulseAnimation = false
                    glowAnimation = false
                }
            }
    }
}

struct PulsingTabHighlight: ViewModifier {
    let isActive: Bool
    
    @State private var pulseAnimation = false
    @State private var glowAnimation = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if isActive {
                        // Pulsing border
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .scaleEffect(pulseAnimation ? 1.08 : 1.0)
                            .opacity(pulseAnimation ? 0.7 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.7)
                                .repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )
                        
                        // Glowing effect
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white, lineWidth: 2)
                            .blur(radius: glowAnimation ? 20 : 10)
                            .opacity(glowAnimation ? 0.9 : 0.5)
                            .animation(
                                .easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                                value: glowAnimation
                            )
                    }
                }
            )
            .scaleEffect(isActive ? 1.05 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
            .onAppear {
                if isActive {
                    DispatchQueue.main.async {
                        pulseAnimation = true
                        glowAnimation = true
                    }
                }
            }
            .onChange(of: isActive) { newValue in
                if newValue {
                    DispatchQueue.main.async {
                        pulseAnimation = true
                        glowAnimation = true
                    }
                } else {
                    pulseAnimation = false
                    glowAnimation = false
                }
            }
    }
}

struct PulsingPlusHighlight: ViewModifier {
    let isActive: Bool
    
    @State private var pulseAnimation = false
    @State private var ringAnimation = false
    @State private var glowAnimation = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if isActive {
                        // Multiple expanding rings
                        ForEach(0..<3) { index in
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.8 - Double(index) * 0.2),
                                            Color.white.opacity(0.4 - Double(index) * 0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .scaleEffect(ringAnimation ? 1.0 + Double(index) * 0.15 : 0.8)
                                .opacity(ringAnimation ? 0 : 0.8 - Double(index) * 0.2)
                                .animation(
                                    .easeOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.2),
                                    value: ringAnimation
                                )
                        }
                        
                        // Core pulsing circle
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .scaleEffect(pulseAnimation ? 1.1 : 1.0)
                            .opacity(pulseAnimation ? 0.8 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true),
                                value: pulseAnimation
                            )
                        
                        // Glow effect
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .blur(radius: 20)
                            .scaleEffect(glowAnimation ? 1.3 : 1.0)
                            .opacity(glowAnimation ? 0.6 : 0.3)
                            .animation(
                                .easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: true),
                                value: glowAnimation
                            )
                    }
                }
            )
            .scaleEffect(isActive ? 1.08 : 1.0)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isActive)
            .onAppear {
                if isActive {
                    DispatchQueue.main.async {
                        pulseAnimation = true
                        ringAnimation = true
                        glowAnimation = true
                    }
                }
            }
            .onChange(of: isActive) { newValue in
                if newValue {
                    DispatchQueue.main.async {
                        pulseAnimation = true
                        ringAnimation = true
                        glowAnimation = true
                    }
                } else {
                    pulseAnimation = false
                    ringAnimation = false
                    glowAnimation = false
                }
            }
    }
}

extension View {
    func pulsingHighlight(isActive: Bool, color: Color = .white) -> some View {
        modifier(PulsingHighlight(isActive: isActive, color: color))
    }
    
    func pulsingTabHighlight(isActive: Bool) -> some View {
        modifier(PulsingTabHighlight(isActive: isActive))
    }
    
    func pulsingPlusHighlight(isActive: Bool) -> some View {
        modifier(PulsingPlusHighlight(isActive: isActive))
    }
}