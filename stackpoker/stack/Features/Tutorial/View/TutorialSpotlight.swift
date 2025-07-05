import SwiftUI

struct TutorialSpotlight: View {
    let isActive: Bool
    let targetFrame: CGRect
    let cornerRadius: CGFloat
    
    @State private var animationPhase = 0.0
    
    var body: some View {
        if isActive {
            GeometryReader { geometry in
                overlayContent(size: geometry.size)
                    .onAppear {
                        animateRipple()
                    }
            }
        }
    }
    
    @ViewBuilder
    private func overlayContent(size: CGSize) -> some View {
        ZStack {
            // Dark overlay with cutout
            SpotlightOverlay(
                targetFrame: targetFrame,
                cornerRadius: cornerRadius,
                size: size
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            // Animated ripple effects
            rippleEffects
                .allowsHitTesting(false)
        }
    }
    
    private var rippleEffects: some View {
        ZStack {
            ForEach(0..<3) { index in
                RippleEffect(
                    index: index,
                    targetFrame: targetFrame,
                    cornerRadius: cornerRadius,
                    animationPhase: animationPhase
                )
            }
        }
    }
    
    private func animateRipple() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: false)) {
            animationPhase = 1.0
        }
    }
}

// Separate view for the overlay
struct SpotlightOverlay: View {
    let targetFrame: CGRect
    let cornerRadius: CGFloat
    let size: CGSize
    
    var body: some View {
        ZStack {
            // Lighter overlay
            Color.black.opacity(0.4)
                .mask(
                    ZStack {
                        // Full screen rectangle
                        Rectangle()
                            .fill(Color.white)
                        
                        // Cutout for spotlight
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.black)
                            .frame(width: targetFrame.width, height: targetFrame.height)
                            .position(x: targetFrame.midX, y: targetFrame.midY)
                    }
                    .compositingGroup()
                    .luminanceToAlpha()
                )
            
            // Glow effect around cutout
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.purple.opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .blur(radius: 20)
                .frame(width: targetFrame.width, height: targetFrame.height)
                .position(x: targetFrame.midX, y: targetFrame.midY)
        }
    }
}

// Separate view for ripple effects
struct RippleEffect: View {
    let index: Int
    let targetFrame: CGRect
    let cornerRadius: CGFloat
    let animationPhase: Double
    
    private var rippleScale: Double {
        1.0 + (Double(index) * 0.15) + animationPhase * 0.3
    }
    
    private var rippleOpacity: Double {
        (0.3 - Double(index) * 0.1) * (1.0 - animationPhase)
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(rippleOpacity),
                        Color.purple.opacity(rippleOpacity * 0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .frame(
                width: targetFrame.width * rippleScale,
                height: targetFrame.height * rippleScale
            )
            .position(
                x: targetFrame.midX,
                y: targetFrame.midY
            )
            .opacity(rippleOpacity)
    }
}

// View modifier for easy application
struct SpotlightModifier: ViewModifier {
    let isActive: Bool
    let cornerRadius: CGFloat
    
    @State private var targetFrame: CGRect = .zero
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(
                            key: FramePreferenceKey.self,
                            value: geometry.frame(in: .global)
                        )
                }
            )
            .onPreferenceChange(FramePreferenceKey.self) { frame in
                targetFrame = frame
            }
            .overlay(
                TutorialSpotlight(
                    isActive: isActive,
                    targetFrame: targetFrame,
                    cornerRadius: cornerRadius
                )
                .allowsHitTesting(false)
            )
    }
}

// Preference key for frame tracking
struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    func tutorialSpotlight(isActive: Bool, cornerRadius: CGFloat = 12) -> some View {
        modifier(SpotlightModifier(isActive: isActive, cornerRadius: cornerRadius))
    }
}