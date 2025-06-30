import SwiftUI

struct TutorialOverlay: View {
    @ObservedObject var tutorialManager: TutorialManager
    @State private var showContent = false
    
    var body: some View {
        if tutorialManager.isActive {
            ZStack {
                // Ultra-light overlay that doesn't interfere
                Color.black.opacity(0.02)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                
                // Smart positioned tooltip
                GeometryReader { geometry in
                    SmartTooltip(
                        step: tutorialManager.currentStep,
                        geometry: geometry,
                        onNext: {
                            if !tutorialManager.currentStep.requiresUserAction {
                                tutorialManager.advanceStep()
                            }
                        },
                        onSkip: {
                            tutorialManager.skipTutorial()
                        }
                    )
                    .opacity(showContent ? 1 : 0)
                    .scaleEffect(showContent ? 1 : 0.9)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showContent)
                }
                .allowsHitTesting(true)
            }
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
                    showContent = true
                }
            }
            .onChange(of: tutorialManager.currentStep) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    showContent = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        showContent = true
                    }
                }
            }
        }
    }
}

struct SmartTooltip: View {
    let step: TutorialManager.TutorialStep
    let geometry: GeometryProxy
    let onNext: () -> Void
    let onSkip: () -> Void
    
    private var tooltipPosition: TooltipPosition {
        switch step {
        case .welcome, .finalWelcome:
            return .center
        case .expandMenu:
            return .bottomCenter(offset: -100) // Above + button
        case .menuExplanation:
            return .topCenter(offset: CGPoint(x: 0, y: 150)) // Above menu, not overlapping
        case .exploreTab:
            // Position directly above the calendar icon in the bottom tab bar
            // Tab bar has 4 tabs + center + button: Feed, Events, +, Groups, Profile
            // Events is the 2nd tab, so it's at position 1 in a 5-item layout
            let screenWidth = geometry.size.width
            let tabBarHeight: CGFloat = 100 // Tab bar height including safe area
            let paddingHorizontal: CGFloat = 20 // Tab bar horizontal padding
            let usableWidth = screenWidth - (paddingHorizontal * 2)
            let buttonWidth = usableWidth / 5 // 5 items total (4 tabs + 1 + button)
            let eventsTabCenter = paddingHorizontal + (buttonWidth * 1.5) // Second tab center
            return .custom(CGPoint(x: eventsTabCenter, y: geometry.size.height - tabBarHeight - 60))
        case .groupsTab:
            // Position above groups tab (4th tab, index 3)
            let screenWidth = geometry.size.width
            let tabBarHeight: CGFloat = 100
            let paddingHorizontal: CGFloat = 20
            let usableWidth = screenWidth - (paddingHorizontal * 2)
            let buttonWidth = usableWidth / 5
            let groupsTabCenter = paddingHorizontal + (buttonWidth * 3.5) // Fourth tab center
            return .custom(CGPoint(x: groupsTabCenter, y: geometry.size.height - tabBarHeight - 60))
        case .profileTab:
            // Position above profile tab (5th tab, index 4)
            let screenWidth = geometry.size.width
            let tabBarHeight: CGFloat = 100
            let paddingHorizontal: CGFloat = 20
            let usableWidth = screenWidth - (paddingHorizontal * 2)
            let buttonWidth = usableWidth / 5
            let profileTabCenter = paddingHorizontal + (buttonWidth * 4.5) // Fifth tab center
            return .custom(CGPoint(x: profileTabCenter, y: geometry.size.height - tabBarHeight - 60))
        case .profileSessions, .profileStakings, .profileAnalytics, .profileChallenges:
            return .topLeading(offset: CGPoint(x: 20, y: 100)) // Top left, clear of content
        case .completed:
            return .center
        }
    }
    
    var body: some View {
        VStack {
            switch tooltipPosition {
            case .center:
                Spacer()
                tooltipContent
                Spacer()
                
            case .topLeading(let offset):
                VStack {
                    HStack {
                        tooltipContent
                            .offset(x: offset.x, y: offset.y)
                        Spacer()
                    }
                    Spacer()
                }
                
            case .topCenter(let offset):
                VStack {
                    tooltipContent
                        .offset(x: offset.x, y: offset.y)
                    Spacer()
                }
                
            case .bottomCenter(let yOffset):
                VStack {
                    Spacer()
                    tooltipContent
                        .offset(y: yOffset)
                }
                
            case .bottomTrailing(let offset):
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        tooltipContent
                            .offset(x: offset.x, y: offset.y)
                    }
                }
                
            case .custom(let position):
                // Position tooltip at exact coordinates
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        tooltipContent
                        Spacer()
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: position.x - geometry.size.width / 2, y: position.y - geometry.size.height / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var tooltipContent: some View {
        VStack(spacing: shouldShowButton ? 12 : 0) {
            // Slim text - no title, just description
            Text(slimmedText)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, isWelcomeStep ? 20 : 12)
            
            // Minimal button design
            if shouldShowButton {
                HStack(spacing: 10) {
                    if step == .welcome {
                        Button("Next") { onNext() }
                            .buttonStyle(PrimaryTutorialButtonStyle())
                        
                        Button("Skip") { onSkip() }
                            .buttonStyle(SecondaryTutorialButtonStyle())
                    } else {
                        Button(step == .finalWelcome ? "Get Started" : "Next") { onNext() }
                            .buttonStyle(PrimaryTutorialButtonStyle())
                    }
                }
            }
        }
        .padding(.vertical, isWelcomeStep ? 16 : 10)
        .padding(.horizontal, isWelcomeStep ? 20 : 14)
        .background(
            RoundedRectangle(cornerRadius: isWelcomeStep ? 14 : 10)
                .fill(.ultraThinMaterial)
                .background(
                    RoundedRectangle(cornerRadius: isWelcomeStep ? 14 : 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                                    Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.3), radius: 12, y: 4)
        )
        .frame(maxWidth: isWelcomeStep ? 280 : 200)
    }
    
    private var slimmedText: String {
        switch step {
        case .welcome:
            return "Let's show you around"
        case .expandMenu:
            return "Tap the + button"
        case .menuExplanation:
            return "Record and track poker activities"
        case .exploreTab:
            return "Tap Events"
        case .groupsTab:
            return "Join communities and games"
        case .profileTab:
            return "View your stats"
        case .profileSessions:
            return "View and track sessions"
        case .profileStakings:
            return "Manage backing deals"
        case .profileAnalytics:
            return "Performance insights"
        case .profileChallenges:
            return "Set goals and compete"
        case .finalWelcome:
            return "You're all ready!"
        case .completed:
            return "All set!"
        }
    }
    
    private var isWelcomeStep: Bool {
        step == .welcome || step == .finalWelcome
    }
    
    private var shouldShowButton: Bool {
        !step.requiresUserAction
    }
}

enum TooltipPosition {
    case center
    case topLeading(offset: CGPoint)
    case topCenter(offset: CGPoint)
    case bottomCenter(offset: CGFloat)
    case bottomTrailing(offset: CGPoint)
    case custom(CGPoint) // New case for exact positioning
}

// Sleek button styles
struct PrimaryTutorialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.white)
                    .shadow(color: .white.opacity(0.3), radius: 8, y: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SecondaryTutorialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
} 