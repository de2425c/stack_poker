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
                
                // Observer for tutorial completion to trigger CSV import
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("TutorialCompleted"),
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
            EnhancedLiveSessionView(userId: userId, sessionStore: sessionStore)
        }
        .fullScreenCover(isPresented: $showingCSVImportFlow) {
            CSVImportFlow(userId: userId)
        }
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

struct CustomTabBar: View {
    @Binding var selectedTab: HomePage.Tab
    let userId: String
    @Binding var showingMenu: Bool
    let tutorialManager: TutorialManager

    var body: some View {
        ZStack {
            // Background color for the tab bar - now nearly transparent to capture touches
            Color.black.opacity(0.01)
                .frame(height: 80) // Increased height to accommodate larger icons and padding
                .edgesIgnoringSafeArea(.bottom) // Extend to the bottom edge

            // Tab buttons
            HStack {
                TabBarButton(
                    icon: "Feed", // Changed to asset name
                    isSelected: selectedTab == .feed,
                    action: { selectedTab = .feed },
                    tutorialManager: tutorialManager
                )

                TabBarButton(
                    icon: "Events", // Changed to calendar/events icon
                    isSelected: selectedTab == .explore,
                    action: { 
                        selectedTab = .explore
                        tutorialManager.userDidAction(.tappedExploreTab)
                    },
                    tutorialManager: tutorialManager
                )

                // Plus button
                AddButton(userId: userId, showingMenu: $showingMenu, tutorialManager: tutorialManager)
                    .padding(.horizontal, 20) // Add some spacing around the plus button


                TabBarButton(
                    icon: "Groups", // Changed to asset name
                    isSelected: selectedTab == .groups,
                    action: { 
                        selectedTab = .groups
                        tutorialManager.userDidAction(.tappedGroupsTab)
                    },
                    tutorialManager: tutorialManager
                )

                TabBarButton(
                    icon: "Profile", // Changed to asset name
                    isSelected: selectedTab == .profile,
                    action: { 
                        selectedTab = .profile
                        tutorialManager.userDidAction(.tappedProfileTab)
                    },
                    tutorialManager: tutorialManager
                )
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 80) // Ensure ZStack respects the increased height
        .padding(.bottom, 20) // Increased bottom padding to move tab bar higher
    }
}

struct TabBarButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    let tutorialManager: TutorialManager?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) { 
                Group {
                    if icon == "Events" {
                        // Use system calendar icon for Events tab
                        Image(systemName: "calendar")
                            .font(.system(size: 25, weight: .medium))
                    } else {
                        // Use asset image for other tabs
                        Image(icon)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30, height: 30)
                    }
                }
                .foregroundColor(isSelected ? .white : Color.gray.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
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
        .tutorialPlusHighlight(isHighlighted: tutorialManager.currentStep == .expandMenu)
    }
}

struct SleekMenuButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 0.95)))
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.green.opacity(0.25), radius: 12, y: 4)
                        .overlay(
                            Circle()
                                .stroke(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)), lineWidth: 2)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color.green.opacity(0.18), radius: 2, y: 1)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

// Break out the title view
struct HandTitleView: View {
    var body: some View {
        HStack {
            Text("Add Hand History")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

// Break out the text editor
struct HandTextEditorView: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .focused($isFocused)
                .foregroundColor(.white)
                .font(.system(size: 15, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(16)
                .frame(minHeight: 180, maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(red: 0.1, green: 0.1, blue: 0.14))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isFocused ? 
                                Color(red: 123/255, green: 255/255, blue: 99/255) : 
                                Color(white: 0.3), 
                            lineWidth: isFocused ? 2 : 1
                        )
                )
            
            if text.isEmpty && !isFocused {
                Text("Paste your hand history here...")
                    .foregroundColor(Color.gray)
                    .font(.system(size: 15, design: .default))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}



struct ProfileScreen: View {
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var authViewModel: AuthViewModel
    let userId: String
    @State private var showEdit = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
                VStack(spacing: 0) {
                    // STACK logo at the top with back button
                    HStack {
                        // Back button
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 0.7)))
                                )
                        }
                        .padding(.leading, 16)
                        
                        Spacer()
                        
                        // Centered STACK logo
                        Text("STACK")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Empty space to balance layout
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 38, height: 38)
                            .padding(.trailing, 16)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 25)
                    .frame(maxWidth: .infinity, alignment: .center)
                    
                    Spacer(minLength: 0)
                    if let profile = userService.currentUserProfile {
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                    .frame(width: 120, height: 120)
                                    .shadow(color: Color.green.opacity(0.18), radius: 12, y: 4)
                                if let url = profile.avatarURL, let imageURL = URL(string: url) {
                                    ProfileImageView(url: imageURL)
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                        .id(profile.avatarURL)
                                } else {
                                    PlaceholderAvatarView(size: 110, iconColor: Color.green.opacity(0.5))
                                }
                            }
                            .padding(.bottom, 8)
                            
                            VStack(spacing: 6) {
                                if let displayName = profile.displayName, !displayName.isEmpty {
                                    Text(displayName)
                                        .font(.system(size: 28, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                
                                Text("@\(profile.username)")
                                    .font(.system(size: displayNameVisible(profile) ? 18 : 28, weight: displayNameVisible(profile) ? .medium : .bold, design: .rounded))
                                    .foregroundColor(.gray)
                                    
                                // Bio and hyperlink combined
                                VStack(spacing: 8) {
                                    if let bio = profile.bio, !bio.isEmpty {
                                        Text(bio)
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.85))
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 24)
                                    }
                                    
                                    // Simple hyperlink - just colored text
                                    if let hyperlinkText = profile.hyperlinkText, !hyperlinkText.isEmpty,
                                       let hyperlinkURL = profile.hyperlinkURL, !hyperlinkURL.isEmpty {
                                        Button(action: {
                                            // Ensure URL has proper scheme
                                            var urlString = hyperlinkURL
                                            if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
                                                urlString = "https://" + urlString
                                            }
                                            
                                            if let url = URL(string: urlString) {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            Text(hyperlinkText)
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.blue)
                                                .underline()
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.top, 12)
                            }
                            
                            HStack(spacing: 32) {
                                NavigationLink(destination: FollowListView(userId: userId, listType: .followers)) {
                                    VStack(spacing: 8) {
                                        Text("\(profile.followersCount)")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("Followers")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                NavigationLink(destination: FollowListView(userId: userId, listType: .following)) {
                                    VStack(spacing: 8) {
                                        Text("\(profile.followingCount)")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("Following")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(.top, 12)
                            
                            if let game = profile.favoriteGame {
                                Text("Favorite Game: \(game)")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                    )
                            }
                            
                            // Edit Profile button
                            Button(action: { showEdit = true }) {
                                HStack {
                                    Image(systemName: "pencil")
                                    Text("Edit Profile")
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 32)
                                .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .cornerRadius(22)
                                .shadow(color: Color.green.opacity(0.18), radius: 6, y: 2)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 32)
                                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 0.95)))
                                .shadow(color: .black.opacity(0.18), radius: 16, y: 4)
                        )
                        .padding(.horizontal, 18)
                        .padding(.top, 0)
                    } else {
                        ProgressView().onAppear {
                            Task { try? await userService.fetchUserProfile() }
                        }
                    }
                    
                    Spacer()
                    
                    // Sign out button at the bottom right
                    HStack {
                        Spacer()
                        
                        Button(action: signOut) {
                            HStack(spacing: 6) {
                                Text("Sign Out")
                                    .font(.system(size: 14, weight: .medium))
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 14))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 0.7)))
                            )
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                if let profile = userService.currentUserProfile {
                    ProfileEditView(profile: profile) { updated in
                        Task { try? await userService.updateUserProfile(updated.dictionary ?? [:]) }
                        showEdit = false
                        Task { try? await userService.fetchUserProfile() }
                    }
                    .environmentObject(userService)
                }
            }
            .navigationBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .navigationTitle("")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // Helper function to check if display name is visible
    private func displayNameVisible(_ profile: UserProfile) -> Bool {
        return profile.displayName != nil && !profile.displayName!.isEmpty
    }
    
    private func signOut() {
        // Use the AuthViewModel's signOut method for proper cleanup
        authViewModel.signOut()
    }
}

struct ProfileImageView: View {
    let url: URL
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var error: Error?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .gray))
            } else {
                Color.gray.opacity(0.3)
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        isLoading = true
        error = nil
        
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {

                    self.error = error
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {

                    return
                }
                
                if let data = data, let uiImage = UIImage(data: data) {
                    self.image = uiImage
                }
            }
        }.resume()
    }
}

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
                                Image(systemName: "xmark")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(Color(white: 0.7))
                                    .padding(10)
                                    .background(
                                        Circle()
                                            .fill(Color.clear)
                                    )
                            }
                            .tutorialPlusHighlight(isHighlighted: tutorialManager.currentStep == .menuExplanation)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                            .padding(.trailing, 20)
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



// MARK: - Game Invites Components

struct GameInvitesBar: View {
    let invites: [HomeGame.GameInvite]
    let onTap: (HomeGame.GameInvite) -> Void
    let isFirstBar: Bool // Whether this is the first bar (no other bars above it)
    
    private var firstInvite: HomeGame.GameInvite? {
        invites.first
    }
    
    var body: some View {
        if let invite = firstInvite {
            Button(action: {
                print("🔥 GameInvitesBar button tapped!")
                onTap(invite)
            }) {
                HStack(spacing: 16) {
                    // Invite icon
                    Circle()
                        .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.black)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Game Invite")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            if invites.count > 1 {
                                Text("+\(invites.count - 1) more")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.2))
                                    )
                            }
                        }
                        
                        Text("\(invite.hostName) invited you to \"\(invite.gameTitle)\"")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.top, isFirstBar ? (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.top ?? 0 : 0)
                .background(
                    Color(UIColor(red: 28/255, green: 30/255, blue: 34/255, alpha: 0.95))
                        .ignoresSafeArea(edges: isFirstBar ? .top : [])
                        .overlay(
                            Rectangle()
                                .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .frame(height: 1),
                            alignment: .bottom
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .onTapGesture {
                print("🔥 FALLBACK: GameInvitesBar tapped via onTapGesture!")
                onTap(invite)
            }
        }
    }
}

// MARK: - New Floating Invite Popup (Replaces the problematic sheet)

struct FloatingInvitePopup: View {
    let invite: HomeGame.GameInvite
    let onAccept: (Double) -> Void
    let onDecline: () -> Void
    let onDismiss: () -> Void
    
    @State private var buyInAmount = ""
    @State private var isProcessing = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var showPopup = false
    
    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.7)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showPopup = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
            
            // Popup content
            VStack(spacing: 0) {
                // Header with game info
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    
                    VStack(spacing: 8) {
                        Text("Game Invite")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(invite.gameTitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("from \(invite.hostName)")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                        
                        if let message = invite.message, !message.isEmpty {
                            Text("\"\(message)\"")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .italic()
                                .multilineTextAlignment(.center)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                
                // Buy-in input section
                VStack(spacing: 16) {
                    Text("Enter your buy-in amount")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 12) {
                        Text("$")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        TextField("100", text: $buyInAmount)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(.vertical, 16)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(UIColor(red: 45/255, green: 47/255, blue: 52/255, alpha: 1.0)))
                            )
                    }
                    .frame(maxWidth: 200)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                
                // Action buttons
                VStack(spacing: 12) {
                    // Accept button
                    Button(action: handleAccept) {
                        HStack(spacing: 8) {
                            if isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.8)
                            }
                            Text(isProcessing ? "Joining..." : "Accept & Join")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(buyInAmount.isEmpty || isProcessing ? 
                                      Color.gray.opacity(0.5) : 
                                      Color(red: 123/255, green: 255/255, blue: 99/255))
                        )
                    }
                    .disabled(buyInAmount.isEmpty || isProcessing)
                    
                    // Decline button
                    Button(action: handleDecline) {
                        Text("Decline")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .disabled(isProcessing)
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor(red: 30/255, green: 32/255, blue: 36/255, alpha: 0.98)))
            )
            .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 32)
            .scaleEffect(showPopup ? 1.0 : 0.7)
            .opacity(showPopup ? 1.0 : 0.0)
        }
        .onAppear {
            print("🚀 FloatingInvitePopup appeared for invite: \(invite.gameTitle)")
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showPopup = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func handleAccept() {
        guard let amount = Double(buyInAmount), amount > 0 else {
            errorMessage = "Please enter a valid amount"
            showError = true
            return
        }
        
        isProcessing = true
        
        // Animate out and call completion
        withAnimation(.easeInOut(duration: 0.3)) {
            showPopup = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onAccept(amount)
        }
    }
    
    private func handleDecline() {
        isProcessing = true
        
        // Animate out and call completion
        withAnimation(.easeInOut(duration: 0.3)) {
            showPopup = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDecline()
        }
    }
}

// MARK: - CSV Import Prompt Logic Extension
extension HomePage {
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
