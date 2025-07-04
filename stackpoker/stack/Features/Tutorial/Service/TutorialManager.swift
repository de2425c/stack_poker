import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

class TutorialManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentStep: TutorialStep = .welcome
    @Published var completedSteps: Set<TutorialStep> = []
    
    private let db = Firestore.firestore()
    
    enum TutorialStep: String, CaseIterable {
        case welcome = "welcome"
        case expandMenu = "expand_menu"
        case menuExplanation = "menu_explanation"
        case exploreTab = "explore_tab"
        case groupsTab = "groups_tab"
        case profileTab = "profile_tab"
        case profileSessions = "profile_sessions"
        case profileStakings = "profile_stakings"
        case profileAnalytics = "profile_analytics"
        case profileChallenges = "profile_challenges"
        case finalWelcome = "final_welcome"
        case completed = "completed"
        
        var text: String {
            switch self {
            case .welcome:
                return "Welcome to Stack!\nLet's show you around"
            case .expandMenu:
                return "Tap the + button to see your options"
            case .menuExplanation:
                return "This is where you can record and track your poker activities"
            case .exploreTab:
                return "Tap Events to discover poker events and tournaments"
            case .groupsTab:
                return "Tap Groups to join poker communities and games"
            case .profileTab:
                return "Tap Profile to view your stats and achievements"
            case .profileSessions:
                return "Sessions\n\nView and track all your poker sessions"
            case .profileStakings:
                return "Staking\n\nManage your poker backing and investment deals"
            case .profileAnalytics:
                return "Analytics\n\nView your performance charts, session stats, and poker insights"
            case .profileChallenges:
                return "Challenges\n\nSet goals and compete with other players"
            case .finalWelcome:
                return "Welcome to Stack! You're all ready to start your poker journey"
            case .completed:
                return "You're all set!"
            }
        }
        
        var requiresUserAction: Bool {
            switch self {
            case .welcome, .finalWelcome, .profileSessions, .profileStakings, .profileAnalytics, .profileChallenges:
                return false // These have buttons
            default:
                return true // Everything else requires user action
            }
        }
    }
    
    // MARK: - Public Methods
    
    func checkAndStartTutorial(userId: String) async {
        guard !isActive else { 
            print("📝 TutorialManager: Tutorial already active, skipping check")
            return 
        }
        
        // Check if userId is empty (Auth not ready yet)
        guard !userId.isEmpty else {
            print("⏳ TutorialManager: UserId is empty, waiting for Auth to initialize...")
            
            // Wait a bit for Auth to initialize and try again
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            // Get fresh userId from Auth
            guard let currentUserId = Auth.auth().currentUser?.uid, !currentUserId.isEmpty else {
                print("❌ TutorialManager: Still no valid userId after waiting")
                return
            }
            
            print("✅ TutorialManager: Got valid userId after waiting: \(currentUserId)")
            await checkAndStartTutorial(userId: currentUserId)
            return
        }
        
        do {
            let hasCompletedTutorial = try await checkTutorialCompletion(userId: userId)
            await MainActor.run {
                if !hasCompletedTutorial {
                    print("📝 TutorialManager: Starting tutorial for user: \(userId)")
                    self.startTutorial()
                } else {
                    print("📝 TutorialManager: Tutorial already completed for user: \(userId)")
                }
            }
        } catch {
            print("❌ TutorialManager: Error in checkAndStartTutorial: \(error)")
            // In case of any error, don't start the tutorial to avoid issues
        }
    }
    
    func startTutorial() {
        isActive = true
        currentStep = .welcome
        completedSteps.removeAll()
    }
    
    func userDidAction(_ action: TutorialAction) {
        guard isActive else { return }
        
        print("📝 TutorialManager: User action \(action) in step \(currentStep.rawValue)")
        
        switch (currentStep, action) {
        case (.expandMenu, .tappedPlusButton):
            advanceToStep(.menuExplanation)
        case (.exploreTab, .tappedExploreTab):
            advanceToStep(.groupsTab)
        case (.groupsTab, .tappedGroupsTab):
            advanceToStep(.profileTab)
        case (.profileTab, .tappedProfileTab):
            advanceToStep(.profileSessions)
        default:
            print("📝 TutorialManager: No matching action for \(action) in step \(currentStep.rawValue)")
            break
        }
    }
    
    func advanceStep() {
        let allSteps = TutorialStep.allCases
        print("📝 TutorialManager: advanceStep() called - current: \(currentStep.rawValue)")
        
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              currentIndex < allSteps.count - 1 else {
            print("📝 TutorialManager: Reached end of tutorial steps, completing...")
            completeTutorial()
            return
        }
        
        let nextStep = allSteps[currentIndex + 1]
        print("📝 TutorialManager: Auto-advancing from \(currentStep.rawValue) to \(nextStep.rawValue)")
        advanceToStep(nextStep)
        print("📝 TutorialManager: Successfully advanced to \(currentStep.rawValue)")
    }
    
    func skipTutorial() {
        Task {
            if let userId = Auth.auth().currentUser?.uid {
                try? await markTutorialCompleted(userId: userId)
            }
        }
        isActive = false
    }
    
    // MARK: - Private Methods
    
    private func advanceToStep(_ step: TutorialStep) {
        let previousStep = currentStep
        completedSteps.insert(currentStep)
        currentStep = step // Update immediately on current thread
        
        // Force UI update immediately
        self.objectWillChange.send()
        
        print("📝 TutorialManager: Advanced from \(previousStep.rawValue) to \(step.rawValue)")
        print("📝 TutorialManager: isActive = \(self.isActive), currentStep = \(self.currentStep)")
        
        if step == .completed {
            completeTutorial()
        }
    }
    
    private func completeTutorial() {
        isActive = false
        
        Task {
            if let userId = Auth.auth().currentUser?.uid {
                try? await markTutorialCompleted(userId: userId)
                
                // Post notification to trigger recommended users popup
                await MainActor.run {
                    NotificationCenter.default.post(name: NSNotification.Name("TutorialCompleted"), object: nil)
                }
            }
        }
    }
    
    // MARK: - Firestore Methods
    
    private func checkTutorialCompletion(userId: String) async throws -> Bool {
        // Safety check for empty userId
        guard !userId.isEmpty else {
            print("❌ TutorialManager: Cannot check tutorial completion - userId is empty")
            return false
        }
        
        do {
            print("📝 TutorialManager: Checking tutorial completion for user: \(userId)")
            let userDoc = try await db.collection("users").document(userId).getDocument()
            
            // Check if document exists
            guard userDoc.exists else {
                print("📝 TutorialManager: User document doesn't exist, tutorial not completed")
                return false
            }
            
            // Safely get the tutorial completion status
            let isCompleted = userDoc.data()?["tutorialCompleted"] as? Bool ?? false
            print("📝 TutorialManager: Tutorial completion status: \(isCompleted)")
            return isCompleted
            
        } catch {
            print("❌ TutorialManager: Error checking tutorial completion: \(error)")
            // In case of error, assume tutorial is not completed to be safe
            return false
        }
    }
    
    private func markTutorialCompleted(userId: String) async throws {
        do {
            try await db.collection("users").document(userId).updateData([
                "tutorialCompleted": true,
                "tutorialCompletedAt": Timestamp()
            ])
            print("✅ TutorialManager: Successfully marked tutorial as completed for user: \(userId)")
        } catch {
            print("❌ TutorialManager: Error marking tutorial as completed: \(error)")
            throw error
        }
    }
}

enum TutorialAction {
    case tappedPlusButton
    case tappedExploreTab
    case tappedGroupsTab
    case tappedProfileTab
} 