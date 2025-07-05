import SwiftUI

struct AddMenuOverlay: View {
    @Binding var showingMenu: Bool
    let userId: String
    @Binding var showSessionForm: Bool
    @Binding var showingLiveSession: Bool
    @Binding var showingOpenHomeGameFlow: Bool
    let tutorialManager: TutorialManager

    var body: some View {
        ZStack {
            // Dark background overlay
            if showingMenu {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        // During menu explanation, any tap should advance tutorial
                        if tutorialManager.currentStep == .menuExplanation {
                            advanceTutorialFromMenu()
                        } else {
                            closeMenu()
                        }
                    }
                    .transition(.opacity)
            }
            
            // Menu panel
            if showingMenu {
                // Center vertically in the screen
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Menu container
                    VStack(spacing: 0) {
                        // X button at top right and greyed out
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                // During menu explanation, any tap should advance tutorial
                                if tutorialManager.currentStep == .menuExplanation {
                                    advanceTutorialFromMenu()
                                } else {
                                    closeMenu()
                                }
                            }) {
                                ZStack {
                                    // Background circle for better tap target
                                    Circle()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(width: 36, height: 36)
                                    
                                    Image(systemName: "xmark")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .overlay(
                                // Simple highlight ring during tutorial
                                Circle()
                                    .stroke(Color.white.opacity(tutorialManager.currentStep == .menuExplanation ? 0.6 : 0), lineWidth: 2)
                                    .frame(width: 40, height: 40)
                                    .animation(.easeInOut(duration: 0.3), value: tutorialManager.currentStep)
                            )
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                        }
                        
                        VStack(spacing: 16) {
                            // Home Game button
                            MenuRow(
                                icon: "house.fill",
                                title: "Home Game",
                                tutorialManager: tutorialManager,
                                highlightStep: nil,
                                action: {
                                    // During menu explanation, any tap should advance tutorial
                                    if tutorialManager.currentStep == .menuExplanation {
                                        advanceTutorialFromMenu()
                                    } else {
                                        withAnimation(nil) {
                                            showingOpenHomeGameFlow = true
                                            showingMenu = false
                                        }
                                    }
                                }
                            )
                            
                            // Past Session button
                            MenuRow(
                                icon: "clock.arrow.circlepath",
                                title: "Past Session",
                                tutorialManager: tutorialManager,
                                highlightStep: nil,
                                action: {
                                    // During menu explanation, any tap should advance tutorial
                                    if tutorialManager.currentStep == .menuExplanation {
                                        advanceTutorialFromMenu()
                                    } else {
                                        withAnimation(nil) {
                                            showSessionForm = true
                                            showingMenu = false
                                        }
                                    }
                                }
                            )
                            
                            // Live Session button
                            MenuRow(
                                icon: "clock",
                                title: "Live Session",
                                tutorialManager: tutorialManager,
                                highlightStep: nil,
                                action: {
                                    // During menu explanation, any tap should advance tutorial
                                    if tutorialManager.currentStep == .menuExplanation {
                                        advanceTutorialFromMenu()
                                    } else {
                                        withAnimation(nil) {
                                            showingLiveSession = true
                                            showingMenu = false
                                        }
                                    }
                                }
                            )
                            
                            // Bottom padding
                            Color.clear.frame(height: 16)
                        }
                        .padding(.horizontal, 16)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "23262F"))
                    )
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .transition(.opacity)
                .onAppear {
                    // User will close menu manually to advance tutorial
                }
            }
        }
    }
    
    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.2)) {
            showingMenu = false
        }
    }
    
    private func advanceTutorialFromMenu() {
        print("🔄 AdvanceTutorialFromMenu: Current step is \(tutorialManager.currentStep)")
        
        withAnimation(.easeOut(duration: 0.2)) {
            showingMenu = false
        }
        
        if tutorialManager.currentStep == .menuExplanation {
            print("✅ AdvanceTutorialFromMenu: Advancing from menuExplanation step")
            
            // Force the UI to update *before* the delay, then advance the step after the delay.
            // This prevents the user from tapping before the highlight is visible.
            tutorialManager.objectWillChange.send()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.tutorialManager.advanceStep() // Goes to exploreTab
                print("✅ AdvanceTutorialFromMenu: Advanced to \(self.tutorialManager.currentStep)")
            }
        }
    }
}

// Menu row that exactly matches the screenshot
struct MenuRow: View {
    let icon: String
    let title: String
    let tutorialManager: TutorialManager?
    let highlightStep: TutorialManager.TutorialStep?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Main button background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "454959"))
                
                HStack(spacing: 12) {
                    // Icon without container
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .frame(width: 44)
                        .padding(.leading, 4)
                    
                    // Text label
                    Text(title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Chevron icon
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(white: 0.7))
                        .padding(.trailing, 16)
                }
                .padding(.vertical, 10) // Reduced vertical padding for shorter boxes
                .padding(.horizontal, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AddButton: View {
    let userId: String
    @Binding var showingMenu: Bool
    let tutorialManager: TutorialManager

    var body: some View {
        Button(action: {
            tutorialManager.userDidAction(.tappedPlusButton)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingMenu.toggle()
            }
        }) {
            ZStack {
                Circle()
                    .fill(Color(hex: "B1B5C3"))
                    .frame(width: 50, height: 50)

                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .pulsingPlusHighlight(isActive: tutorialManager.currentStep == .expandMenu)
    }
}