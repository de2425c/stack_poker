import SwiftUI
import UIKit

struct TutorialOverlay: View {
    @ObservedObject var tutorialManager: TutorialManager
    @State private var showContent = false
    @State private var spotlightActive = false
    
    var body: some View {
        if tutorialManager.isActive {
            ZStack {
                
                // Enhanced tooltip
                GeometryReader { geometry in
                    GlassMorphismTooltip(
                        title: shouldShowCompactTooltip ? "" : tutorialManager.currentStep.title,
                        message: getTooltipMessage(),
                        step: currentStepIndex + 1,
                        totalSteps: totalSteps,
                        showSkip: tutorialManager.currentStep == .welcome,
                        showButton: !tutorialManager.currentStep.requiresUserAction,
                        onNext: {
                            playHaptic()
                            if !tutorialManager.currentStep.requiresUserAction {
                                tutorialManager.advanceStep()
                            }
                        },
                        onSkip: {
                            playHaptic()
                            tutorialManager.skipTutorial()
                        }
                    )
                    .frame(maxWidth: shouldShowCompactTooltip ? 200 : 280)
                    .position(tooltipPosition(in: geometry))
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1 : 0.8)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showContent)
                }
                .allowsHitTesting(true)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                    showContent = true
                    spotlightActive = true
                }
            }
            .onChange(of: tutorialManager.currentStep) { _ in
                playHaptic()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    showContent = false
                    spotlightActive = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showContent = true
                        spotlightActive = true
                    }
                }
            }
        }
    }
    
    private var shouldShowSpotlight: Bool {
        switch tutorialManager.currentStep {
        case .expandMenu, .exploreTab, .groupsTab, .profileTab:
            return true
        default:
            return false
        }
    }
    
    private func getSpotlightFrame() -> CGRect {
        let screenBounds = UIScreen.main.bounds
        
        switch tutorialManager.currentStep {
        case .expandMenu:
            // Plus button in center of tab bar
            return CGRect(
                x: screenBounds.width / 2 - 30,
                y: screenBounds.height - 100,
                width: 60,
                height: 60
            )
        case .exploreTab:
            // Events tab (2nd position)
            let tabWidth = screenBounds.width / 5
            return CGRect(
                x: tabWidth * 1 + 10,
                y: screenBounds.height - 80,
                width: tabWidth - 20,
                height: 50
            )
        case .groupsTab:
            // Groups tab (4th position)
            let tabWidth = screenBounds.width / 5
            return CGRect(
                x: tabWidth * 3 + 10,
                y: screenBounds.height - 80,
                width: tabWidth - 20,
                height: 50
            )
        case .profileTab:
            // Profile tab (5th position)
            let tabWidth = screenBounds.width / 5
            return CGRect(
                x: tabWidth * 4 + 10,
                y: screenBounds.height - 80,
                width: tabWidth - 20,
                height: 50
            )
        default:
            return .zero
        }
    }
    
    private func getSpotlightCornerRadius() -> CGFloat {
        switch tutorialManager.currentStep {
        case .expandMenu:
            return 30
        default:
            return 12
        }
    }
    
    private func tooltipPosition(in geometry: GeometryProxy) -> CGPoint {
        let safeAreaTop = geometry.safeAreaInsets.top
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        
        switch tutorialManager.currentStep {
        case .welcome, .finalWelcome:
            return CGPoint(x: screenWidth / 2, y: screenHeight / 2)
            
        case .expandMenu:
            // Position above the + button with safe area consideration
            return CGPoint(x: screenWidth / 2, y: screenHeight - safeAreaBottom - 160)
            
        case .menuExplanation:
            // Position higher to avoid X button overlap
            return CGPoint(x: screenWidth / 2, y: safeAreaTop + 150)
            
        case .exploreTab:
            // Position to the right of Events tab to avoid cutoff
            return CGPoint(x: min(screenWidth * 0.35, screenWidth - 150), y: screenHeight - safeAreaBottom - 160)
            
        case .groupsTab:
            // Position above Groups tab (4th position in tab bar)
            let tabWidth = screenWidth / 5
            return CGPoint(x: tabWidth * 3.5, y: screenHeight - safeAreaBottom - 160)
            
        case .profileTab:
            // Position directly above Profile tab (5th position)
            let tabWidth = screenWidth / 5
            return CGPoint(x: tabWidth * 4.5, y: screenHeight - safeAreaBottom - 160)
            
        case .profileOverview:
            // Position at top of screen to avoid overlapping content
            return CGPoint(x: screenWidth / 2, y: safeAreaTop + 100)
            
        case .exploreExplanation, .groupsExplanation:
            // Center position for explanation screens
            return CGPoint(x: screenWidth / 2, y: screenHeight / 2)
            
        default:
            return CGPoint(x: screenWidth / 2, y: screenHeight / 2)
        }
    }
    
    private var currentStepIndex: Int {
        // Get only the main steps, excluding explanation steps
        let mainSteps: [TutorialManager.TutorialStep] = [
            .welcome, .expandMenu, .menuExplanation, .exploreTab, 
            .groupsTab, .profileTab, .profileOverview, .finalWelcome
        ]
        return mainSteps.firstIndex(of: tutorialManager.currentStep) ?? 0
    }
    
    private var totalSteps: Int {
        8 // Total number of main steps excluding explanations
    }
    
    private func playHaptic() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private var shouldShowCompactTooltip: Bool {
        switch tutorialManager.currentStep {
        case .expandMenu, .exploreTab, .groupsTab, .profileTab:
            return true
        default:
            return false
        }
    }
    
    private func getTooltipMessage() -> String {
        return tutorialManager.currentStep.text
    }
}