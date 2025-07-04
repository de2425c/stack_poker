import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import UIKit

// TabBar visibility manager to control tab bar visibility across the app
class TabBarVisibilityManager: ObservableObject {
    @Published var isVisible: Bool = true
}

struct HomePage: View {
    @State private var selectedTab: Tab = .feed
    let userId: String
    @State private var showingMenu = false
    @State private var showingSessionForm = false
    @State private var showingLiveSession = false
    @State private var showingOpenHomeGameFlow = false
    @State private var liveSessionBarExpanded = false
    @StateObject private var sessionStore: SessionStore
    @StateObject private var postService = PostService()
    @StateObject private var tabBarVisibility = TabBarVisibilityManager()
    @StateObject private var tutorialManager = TutorialManager()
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    // Added for HomeGameDetailView presentation
    @StateObject private var pageLevelHomeGameService = HomeGameService()
    @State private var gameForDetailView: HomeGame?
    @State private var showGameDetailView = false
    @State private var activeHostedStandaloneGame: HomeGame?
    
    // Game invites
    @State private var pendingInvites: [HomeGame.GameInvite] = []
    @State private var inviteListener: ListenerRegistration?
    @State private var showingInviteAcceptSheet = false
    @State private var selectedInvite: HomeGame.GameInvite?
    
    // CSV Import Prompt
    @State private var showingCSVImportPrompt = false
    @State private var showingCSVImportFlow = false
    
    // Recommended Users Popup
    @State private var showingRecommendedUsers = false
    
    init(userId: String) {
        self.userId = userId
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
    }
    
    enum Tab {
        case feed
        case explore
        case add
        case groups
        case profile
    }
    
    // Computed properties to simplify complex expressions
    private var hasStandaloneGameBar: Bool {
        let hasGame = activeHostedStandaloneGame != nil
        print("🏠 HomePage Debug - hasStandaloneGameBar: \(hasGame)")
        if let game = activeHostedStandaloneGame {
            print("   Game title: \(game.title)")
        }
        return hasGame
    }
    
    private var hasInviteBar: Bool {
        let hasInvites = !pendingInvites.isEmpty
        print("📧 HomePage Debug - hasInviteBar: \(hasInvites) (invites: \(pendingInvites.count))")
        return hasInvites
    }
    
    private var hasLiveSessionBar: Bool {
        let hasLiveBar = sessionStore.showLiveSessionBar && !sessionStore.liveSession.isEnded && (sessionStore.liveSession.buyIn > 0 || sessionStore.liveSession.isActive)
        print("🎰 HomePage Debug - hasLiveSessionBar: \(hasLiveBar)")
        print("   showLiveSessionBar: \(sessionStore.showLiveSessionBar)")
        print("   isEnded: \(sessionStore.liveSession.isEnded)")
        print("   buyIn: \(sessionStore.liveSession.buyIn)")
        print("   isActive: \(sessionStore.liveSession.isActive)")
        return hasLiveBar
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView(edges: .horizontal)
                    .ignoresSafeArea()
                
                // Dim overlay to darken screen outside the menu (only when menu is showing)
                if showingMenu {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation { showingMenu = false }
                        }
                }
                
                // Main view structure
                VStack(spacing: 0) {
                    // Standalone Home Game Bar (if active) - flush with safe area
                    if let hostedGame = activeHostedStandaloneGame {
                        StandaloneHomeGameBar(game: hostedGame, onTap: {
                            self.gameForDetailView = hostedGame
                            self.showGameDetailView = true
                        })
                    }
                    
                    // Game Invites Bar - flush with safe area or standalone game bar
                    if hasInviteBar {
                        GameInvitesBar(
                            invites: pendingInvites,
                            onTap: { invite in
                                print("🎯 Invite tapped: \(invite.gameTitle)")
                                selectedInvite = invite
                                showingInviteAcceptSheet = true
                                print("🎯 State set - selectedInvite: \(selectedInvite?.gameTitle ?? "nil"), showingInviteAcceptSheet: \(showingInviteAcceptSheet)")
                            },
                            isFirstBar: !hasStandaloneGameBar
                        )
                    }
                    
                    // Live session bar (if active)
                    if hasLiveSessionBar {
                        LiveSessionBar(
                            sessionStore: sessionStore,
                            isExpanded: $liveSessionBarExpanded,
                            onTap: { 
                                // Make sure the session is shown when tapped
                                showingLiveSession = true 
                            },
                            isFirstBar: !hasStandaloneGameBar && !hasInviteBar
                        )
                        .onTapGesture {
                            // Additional tap gesture to ensure it works
                            if !liveSessionBarExpanded {
                                showingLiveSession = true
                            }
                        }
                    }
                    
                    // Main content
                    TabView(selection: $selectedTab) {
                        ZStack {
                            // Extend background fully behind everything
                            AppBackgroundView()
                                .ignoresSafeArea()
                            
                            // Wrap FeedView with padding
                            VStack(spacing: 0) {
                                // Remove extra spacing that could create a black bar
                                
                                // FeedView with transparent background
                                FeedView(
                                    userId: userId,
                                    hasStandaloneGameBar: hasStandaloneGameBar,
                                    hasInviteBar: hasInviteBar,
                                    hasLiveSessionBar: hasLiveSessionBar,
                                    onNavigateToExplore: {
                                        selectedTab = .explore
                                    }
                                )
                                .environmentObject(sessionStore)
                                .environmentObject(tutorialManager)
                                .edgesIgnoringSafeArea(.top)
                            }
                        }
                        .tag(Tab.feed)
                        
                        ExploreView()
                            .environmentObject(sessionStore)
                            .environmentObject(tutorialManager)
                            .tag(Tab.explore)
                        
                        Color.clear // Placeholder for Add tab
                            .tag(Tab.add)
                            .overlay(
                                // Cutout for the + button - positioned at center bottom
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        Circle()
                                            .fill(Color.black.opacity(0.01)) // Nearly transparent
                                            .blendMode(.destinationOut) // This creates the "hole" effect
                                            .frame(width: 70, height: 70)
                                        Spacer()
                                    }
                                    .padding(.bottom, 20)
                                }
                            )
                        
                        GroupsView(
                            hasStandaloneGameBar: hasStandaloneGameBar,
                            hasInviteBar: hasInviteBar,
                            hasLiveSessionBar: hasLiveSessionBar
                        )
                            .environmentObject(userService)
                            .environmentObject(sessionStore)
                            .environmentObject(postService)
                            .environmentObject(tabBarVisibility)
                            .environmentObject(tutorialManager)
                            .tag(Tab.groups)
                        
                        ProfileView(userId: userId)
                            .environmentObject(userService)
                            .environmentObject(sessionStore)
                            .environmentObject(postService)
                            .environmentObject(tabBarVisibility)
                            .environmentObject(tutorialManager)
                            .tag(Tab.profile)
                    }
                    .compositingGroup() // Ensures the blendMode works properly
                    .background(Color.clear)
                    .toolbar(.hidden, for: .tabBar)
                }
                .ignoresSafeArea(edges: .top)

                // Show custom tab bar only when it should be visible
                if tabBarVisibility.isVisible {
                    CustomTabBar(
                        selectedTab: $selectedTab,
                        userId: userId,
                        showingMenu: $showingMenu,
                        tutorialManager: tutorialManager
                    )
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)  // Adjusted for the new tab bar design
                    .opacity(showingMenu ? 0 : 1)
                    .ignoresSafeArea(.keyboard)
                }
                
                // Tutorial overlay (highest z-index)
                TutorialOverlay(tutorialManager: tutorialManager)
                    .zIndex(1002) // Higher than menu popup
                
                if showingMenu {
                    AddMenuOverlay(
                        showingMenu: $showingMenu,
                        userId: userId,
                        showSessionForm: $showingSessionForm,
                        showingLiveSession: $showingLiveSession,
                        showingOpenHomeGameFlow: $showingOpenHomeGameFlow,
                        tutorialManager: tutorialManager
                    )
                    .zIndex(1000) // Below tutorial overlay
                }

                // NavigationLink to HomeGameDetailView (exactly matching GroupsView implementation)
                NavigationLink(
                    destination: Group {
                        if let game = gameForDetailView {
                            ZStack {
                                // Keep AppBackgroundView for consistent background
                                AppBackgroundView()
                                    .ignoresSafeArea()
                                
                                HomeGameDetailView(game: game, onGameUpdated: {
                                    // This callback is triggered from HomeGameDetailView
                                    Task {
                                        if let updatedGame = try? await self.pageLevelHomeGameService.fetchHomeGame(gameId: game.id) {
                                            self.gameForDetailView = updatedGame
                                        }
                                    }
                                    loadActiveHostedStandaloneGame()
                                })
                                .environmentObject(sessionStore)
                            }
                            .navigationBarBackButtonHidden(true)
                        }
                    },
                    isActive: $showGameDetailView
                ) {
                    EmptyView()
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .ignoresSafeArea(.keyboard)
            
            // Lifecycle modifiers MUST be attached to the main view, not to the following conditional content.
            .onAppear {
                pageLevelHomeGameService.startListeningForActiveStandaloneGame(userId: self.userId) { game in
                    DispatchQueue.main.async {
                        self.activeHostedStandaloneGame = game
                    }
                }

                loadActiveHostedStandaloneGame()
                
                // Start listening for game invites
                inviteListener = pageLevelHomeGameService.listenForPendingInvites(userId: userId) { invites in
                    DispatchQueue.main.async {
                        self.pendingInvites = invites
                    }
                }
                
                // Observer for standalone game bar refresh
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("RefreshStandaloneHomeGame"),
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    loadActiveHostedStandaloneGame()
                }
                
                // Observer for tutorial completion to trigger recommended users popup
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("TutorialCompleted"),
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    showRecommendedUsersPopup()
                }
                
                // Observer for recommended users completion to trigger CSV import
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("RecommendedUsersCompleted"),
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    checkForCSVImportPrompt()
                }
                
                // Check and start tutorial (with delay to ensure Auth is ready)
                Task {
                    // Small delay to ensure Firebase Auth is fully initialized
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    
                    // Get the most current userId
                    let currentUserId = Auth.auth().currentUser?.uid ?? userId
                    await tutorialManager.checkAndStartTutorial(userId: currentUserId)
                }
                
                // Check if we should show CSV import prompt (but not during tutorial)
                if !tutorialManager.isActive {
                    checkForCSVImportPrompt()
                }
            }
            .onDisappear {
                // Clean-up observers & listeners
                NotificationCenter.default.removeObserver(self)
                pageLevelHomeGameService.stopListeningForActiveStandaloneGame()
                inviteListener?.remove(); inviteListener = nil
            }
            .environmentObject(tabBarVisibility)
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Use StackNavigationViewStyle for consistent presentation
        .accentColor(.white) // Set navigation bar buttons to white
        // NEW: Floating invite popup overlay (moved outside NavigationView for better positioning)
        .overlay(
            Group {
                if showingInviteAcceptSheet, let invite = selectedInvite {
                    FloatingInvitePopup(
                        invite: invite,
                        onAccept: { amount in
                            handleInviteAccept(invite: invite, amount: amount)
                        },
                        onDecline: {
                            handleInviteDecline(invite: invite)
                        },
                        onDismiss: {
                            showingInviteAcceptSheet = false
                            selectedInvite = nil
                        }
                    )
                }
            }
        )
        // Move all sheet modifiers OUTSIDE NavigationView to prevent white screen issues
        .sheet(isPresented: $showingSessionForm) {
            SessionFormView(userId: userId)
                .environmentObject(sessionStore)
                .environmentObject(userService)
        }
        .sheet(isPresented: $showingOpenHomeGameFlow, onDismiss: {
            // If showing game detail, the sheet dismissal should let the navigation link activate
            if self.gameForDetailView != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.showGameDetailView = true
                }
            }
            
            // Force refresh active game bar on dismissal (whether from cancel or create)
            loadActiveHostedStandaloneGame()
        }) {
            HomeGameView(groupId: nil, onGameCreated: { newGame in
                self.gameForDetailView = newGame
                self.showingOpenHomeGameFlow = false // Dismiss HomeGameView sheet
                
                // Set active hosted game for the banner immediately
                if newGame.status == .active && newGame.creatorId == self.userId {
                    self.activeHostedStandaloneGame = newGame
                }
            })
            .environmentObject(userService)
        }
        .fullScreenCover(isPresented: $showingLiveSession) {
            LiveSessionCoordinatorView(
                userId: userId,
                sessionStore: sessionStore,
                onDismiss: { showingLiveSession = false }
            )
        }
        .fullScreenCover(isPresented: $showingCSVImportFlow) {
            CSVImportFlow(userId: userId)
        }
        // Recommended Users Popup Overlay
        .overlay(
            Group {
                if showingRecommendedUsers {
                    RecommendedUsersPopup(
                        onContinue: {
                            showingRecommendedUsers = false
                            // Navigate to feed tab
                            selectedTab = .feed
                            // Post notification to trigger CSV import after a delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                NotificationCenter.default.post(name: NSNotification.Name("RecommendedUsersCompleted"), object: nil)
                            }
                        },
                        onDismiss: {
                            showingRecommendedUsers = false
                            // Navigate to feed tab even if dismissed
                            selectedTab = .feed
                            // Still trigger CSV import after a delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                NotificationCenter.default.post(name: NSNotification.Name("RecommendedUsersCompleted"), object: nil)
                            }
                        }
                    )
                    .environmentObject(userService)
                    .zIndex(1000) // Higher than CSV import prompt
                }
            }
        )
        // CSV Import Prompt Overlay
        .overlay(
            Group {
                if showingCSVImportPrompt {
                    CSVImportPrompt(
                        onImportSelected: {
                            showingCSVImportPrompt = false
                            showingCSVImportFlow = true
                        },
                        onDismiss: {
                            showingCSVImportPrompt = false
                            // Mark that the user has seen the prompt
                            Task {
                                try? await userService.markCSVPromptShown()
                            }
                        }
                    )
                    .zIndex(999)
                }
            }
        )
        .onAppear {
            // Perform comprehensive session validation asynchronously on app launch
            Task {
                await sessionStore.validateSessionStateOnLaunch()
            }
        }
        // REMOVED: Old sheet presentation that was causing white screen issues
        // The floating popup is now handled as an overlay above
    }
    
    private func loadActiveHostedStandaloneGame() {
        Task {
            do {
                let hosted = try await pageLevelHomeGameService.fetchActiveGames(createdBy: self.userId)
                let playing = try await pageLevelHomeGameService.fetchActiveStandaloneGames(for: self.userId)

                // Only include active standalone games, sorted by creation date (most recent first)
                let all = (hosted + playing)
                    .filter { $0.groupId == nil && $0.status == .active }
                    .sorted { $0.createdAt > $1.createdAt }
                
                await MainActor.run {
                    let previousGame = self.activeHostedStandaloneGame
                    self.activeHostedStandaloneGame = all.first
                    
                    // Debug logging to help track game banner updates
                    if let newGame = self.activeHostedStandaloneGame {
                        print("🎮 Updated active game banner to: \(newGame.title) (ID: \(newGame.id), Status: \(newGame.status.rawValue), Created: \(newGame.createdAt))")
                        if let prev = previousGame, prev.id != newGame.id {
                            print("🔄 Changed from previous game: \(prev.title) (ID: \(prev.id))")
                        }
                    } else {
                        print("🎮 No active standalone games found")
                        if previousGame != nil {
                            print("🔄 Removed previous game from banner")
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    print("❌ Error loading active standalone game: \(error)")
                    self.activeHostedStandaloneGame = nil
                }
            }
        }
    }
    
    private func signOut() {
        // Use the AuthViewModel's signOut method for proper cleanup
        authViewModel.signOut()
    }
    
    // MARK: - Invite Handling Methods
    
    private func handleInviteAccept(invite: HomeGame.GameInvite, amount: Double) {
        Task {
            do {
                // Accept the invite
                _ = try await pageLevelHomeGameService.acceptGameInvite(inviteId: invite.id)
                
                // Request buy-in with the specified amount
                try await pageLevelHomeGameService.requestBuyIn(gameId: invite.gameId, amount: amount)
                
                await MainActor.run {
                    showingInviteAcceptSheet = false
                    selectedInvite = nil
                    
                    // Refresh the home game bar to show the new game the user joined
                    loadActiveHostedStandaloneGame()
                }
            } catch {
                await MainActor.run {
                    // Handle error - could show an alert here
                    print("Error accepting invite: \(error)")
                    showingInviteAcceptSheet = false
                    selectedInvite = nil
                }
            }
        }
    }
    
    private func handleInviteDecline(invite: HomeGame.GameInvite) {
        Task {
            do {
                // Decline the invite
                try await pageLevelHomeGameService.declineGameInvite(inviteId: invite.id)
                
                await MainActor.run {
                    showingInviteAcceptSheet = false
                    selectedInvite = nil
                }
            } catch {
                await MainActor.run {
                    // Handle error - could show an alert here
                    print("Error declining invite: \(error)")
                    showingInviteAcceptSheet = false
                    selectedInvite = nil
                }
            }
        }
    }
}

// MARK: - Recommended Users and CSV Import Logic Extensions
extension HomePage {
    private func showRecommendedUsersPopup() {
        // Ensure we're on the feed tab when showing recommended users
        selectedTab = .feed
        
        // Small delay to allow tab transition to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showingRecommendedUsers = true
        }
    }
    
    private func checkForCSVImportPrompt() {
        Task {
            do {
                // Increment login count and check if we should show the prompt
                let shouldShow = try await userService.incrementLoginCount()
                
                await MainActor.run {
                    if shouldShow {
                        // Delay the prompt slightly to allow the UI to settle
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.showingCSVImportPrompt = true
                        }
                    }
                }
            } catch {
                print("Error checking CSV import prompt: \(error)")
            }
        }
    }
}

// MARK: - Navigation

extension HomePage {
    private func navigateToGameDetail(game: HomeGame) {
        self.gameForDetailView = game
        self.showGameDetailView = true
    }
}

//
// MARK: - Child Views and Overlays
//

private extension HomePage {
    @ViewBuilder
    var gameDetailView: some View {
        // ... existing code ...
    }
}
