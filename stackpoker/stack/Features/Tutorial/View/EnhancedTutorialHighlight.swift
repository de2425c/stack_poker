import SwiftUI

struct EnhancedTutorialHighlight: ViewModifier {
    let isHighlighted: Bool
    let highlightType: HighlightType
    
    @State private var animationPhase = 0.0
    @State private var pulseScale = 1.0
    
    enum HighlightType {
        case tab
        case plus
        case menu
        case general
    }
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if isHighlighted {
                        ZStack {
                            // Animated gradient border
                            shape(for: highlightType)
                                .stroke(
                                    AngularGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.8),
                                            Color.purple.opacity(0.6),
                                            Color.blue.opacity(0.6),
                                            Color.white.opacity(0.8)
                                        ]),
                                        center: .center,
                                        startAngle: .degrees(animationPhase),
                                        endAngle: .degrees(animationPhase + 360)
                                    ),
                                    lineWidth: 3
                                )
                                .blur(radius: 1)
                            
                            // Glow effect
                            shape(for: highlightType)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                                .blur(radius: 8)
                                .scaleEffect(pulseScale)
                            
                            // Inner highlight
                            shape(for: highlightType)
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.1),
                                            Color.clear
                                        ]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: geometry.size.width / 2
                                    )
                                )
                        }
                    }
                }
            )
            .scaleEffect(isHighlighted ? 1.03 : 1.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isHighlighted)
            .onAppear {
                if isHighlighted {
                    startAnimations()
                }
            }
            .onChange(of: isHighlighted) { newValue in
                if newValue {
                    startAnimations()
                }
            }
    }
    
    private func shape(for type: HighlightType) -> AnyShape {
        switch type {
        case .tab, .menu, .general:
            return AnyShape(RoundedRectangle(cornerRadius: 16))
        case .plus:
            return AnyShape(Circle())
        }
    }
    
    private func startAnimations() {
        // Rotation animation
        withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
            animationPhase = 360
        }
        
        // Pulse animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.1
        }
    }
}

extension View {
    func enhancedTutorialHighlight(isHighlighted: Bool, type: EnhancedTutorialHighlight.HighlightType = .general) -> some View {
        self.modifier(EnhancedTutorialHighlight(isHighlighted: isHighlighted, highlightType: type))
    }
}