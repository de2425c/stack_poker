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
    @State private var showingReplay = false
    @State private var replayHand: ParsedHandHistory?
    @State private var showingSessionForm = false
    @State private var showingLiveSession = false
    @State private var showingOpenHomeGameFlow = false
    @State private var liveSessionBarExpanded = false
    @StateObject private var sessionStore: SessionStore
    @StateObject private var handStore: HandStore
    @StateObject private var postService = PostService()
    @StateObject private var tabBarVisibility = TabBarVisibilityManager()
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var authViewModel: AuthViewModel
    
    // Added for HomeGameDetailView presentation
    @StateObject private var pageLevelHomeGameService = HomeGameService()
    @State private var gameForDetailView: HomeGame?
    @State private var showGameDetailView = false
    @State private var activeHostedStandaloneGame: HomeGame?
    
    init(userId: String) {
        self.userId = userId
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }
    
    enum Tab {
        case feed
        case explore
        case add
        case groups
        case profile
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
                    // Standalone Home Game Bar (if active)
                    if let hostedGame = activeHostedStandaloneGame {
                        StandaloneHomeGameBar(game: hostedGame, onTap: {
                            self.gameForDetailView = hostedGame
                            self.showGameDetailView = true
                        })
                        .padding(.top, (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.top ?? 0)
                    }
                    
                    // Live session bar (if active)
                    if sessionStore.showLiveSessionBar && !sessionStore.liveSession.isEnded && 
                       (sessionStore.liveSession.buyIn > 0 || sessionStore.liveSession.isActive) {
                        LiveSessionBar(
                            sessionStore: sessionStore,
                            isExpanded: $liveSessionBarExpanded,
                            onTap: { 
                                // Make sure the session is shown when tapped
                                print("LiveSessionBar tapped - opening session")
                                showingLiveSession = true 
                            }
                        )
                        .onTapGesture {
                            // Additional tap gesture to ensure it works
                            if !liveSessionBarExpanded {
                                print("LiveSessionBar tapped via gesture - opening session")
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
                                FeedView(userId: userId)
                                    .edgesIgnoringSafeArea(.top)
                            }
                        }
                        .tag(Tab.feed)
                        
                        ExploreView()
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
                        
                        GroupsView()
                            .environmentObject(userService)
                            .environmentObject(handStore)
                            .environmentObject(sessionStore)
                            .environmentObject(postService)
                            .environmentObject(tabBarVisibility)
                            .tag(Tab.groups)
                        
                        ProfileView(userId: userId)
                            .environmentObject(userService)
                            .environmentObject(handStore)
                            .environmentObject(sessionStore)
                            .environmentObject(postService)
                            .environmentObject(tabBarVisibility)
                            .tag(Tab.profile)
                    }
                    .compositingGroup() // Ensures the blendMode works properly
                    .background(Color.clear)
                    .toolbar(.hidden, for: .tabBar)
                }

                // Show custom tab bar only when it should be visible
                if tabBarVisibility.isVisible {
                    CustomTabBar(
                        selectedTab: $selectedTab,
                        userId: userId,
                        showingMenu: $showingMenu
                    )
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 10)  // Adjusted for the new tab bar design
                    .opacity(showingReplay ? 0 : 1)
                    .ignoresSafeArea(.keyboard)
                }
                
                if showingMenu {
                    AddMenuOverlay(
                        showingMenu: $showingMenu,
                        userId: userId,
                        showSessionForm: $showingSessionForm,
                        showingLiveSession: $showingLiveSession,
                        showingOpenHomeGameFlow: $showingOpenHomeGameFlow
                    )
                    .zIndex(1)
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
            .fullScreenCover(isPresented: $showingReplay) {
                if let hand = replayHand {
                    HandReplayView(hand: hand, userId: userId)
                }
            }
            .sheet(isPresented: $showingSessionForm) {
                SessionFormView(userId: userId)
            }
            .sheet(isPresented: $showingOpenHomeGameFlow, onDismiss: {
                // If showing game detail, the sheet dismissal should let the navigation link activate
                if self.gameForDetailView != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.showGameDetailView = true
                    }
                }
                
                // Force refresh active game bar on dismissal (whether from cancel or create)
                print("⚡️ Force refreshing active games on sheet dismiss")
                loadActiveHostedStandaloneGame()
            }) {
                HomeGameView(groupId: nil, onGameCreated: { newGame in
                    self.gameForDetailView = newGame
                    self.showingOpenHomeGameFlow = false // Dismiss HomeGameView sheet
                    
                    // Set active hosted game for the banner immediately
                    if newGame.status == .active && newGame.creatorId == self.userId {
                        print("⚡️ DIRECTLY setting active standalone game: \(newGame.title)")
                        self.activeHostedStandaloneGame = newGame
                    }
                })
                .environmentObject(userService)
            }
            .fullScreenCover(isPresented: $showingLiveSession) {
                EnhancedLiveSessionView(userId: userId, sessionStore: sessionStore)
            }
            .onAppear {
                loadActiveHostedStandaloneGame()
                
                // Add observer for standalone game bar refresh
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("RefreshStandaloneHomeGame"),
                    object: nil,
                    queue: .main
                ) { [self] _ in
                    loadActiveHostedStandaloneGame()
                }
            }
            .onDisappear {
                // Remove observer when view disappears
                NotificationCenter.default.removeObserver(self)
            }
            .environmentObject(tabBarVisibility)
        }
        .accentColor(.white) // Set navigation bar buttons to white
        .navigationViewStyle(StackNavigationViewStyle()) // Use StackNavigationViewStyle for consistent presentation
    }
    
    private func loadActiveHostedStandaloneGame() {
        print("⚡️ Loading active hosted standalone games...")
        Task {
            do {
                let allHostedGames = try await pageLevelHomeGameService.fetchActiveGames(createdBy: self.userId)
                print("⚡️ Found \(allHostedGames.count) active games hosted by user")
                
                // Get standalone games (no groupId) that are active and sort by creation date (newest first)
                let standaloneGames = allHostedGames
                    .filter { $0.groupId == nil && $0.status == .active }
                    .sorted { $0.createdAt > $1.createdAt }
                
                print("⚡️ Filtered to \(standaloneGames.count) standalone active games")
                
                await MainActor.run {
                    // Get the most recent one
                    self.activeHostedStandaloneGame = standaloneGames.first
                    
                    if let game = self.activeHostedStandaloneGame {
                        print("⚡️ Set active game: \(game.title) (created \(game.createdAt))")
                    } else {
                        print("⚡️ No active standalone games found")
                    }
                }
            } catch {
                print("⚡️ Error fetching active hosted standalone games: \(error.localizedDescription)")
                await MainActor.run {
                    self.activeHostedStandaloneGame = nil // Ensure it's nil on error
                }
            }
        }
    }
    
    private func signOut() {
        // Use the AuthViewModel's signOut method for proper cleanup
        authViewModel.signOut()
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: HomePage.Tab
    let userId: String
    @Binding var showingMenu: Bool

    var body: some View {
        ZStack {
            // Background color for the tab bar - now transparent
            Color.clear
                .frame(height: 80) // Increased height to accommodate larger icons and padding
                .edgesIgnoringSafeArea(.bottom) // Extend to the bottom edge

            // Tab buttons
            HStack {
                TabBarButton(
                    icon: "Feed", // Changed to asset name
                    isSelected: selectedTab == .feed
                ) { selectedTab = .feed }

                TabBarButton(
                    icon: "Search", // Changed to asset name
                    isSelected: selectedTab == .explore
                ) { selectedTab = .explore }

                // Plus button
                AddButton(userId: userId, showingMenu: $showingMenu)
                    .padding(.horizontal, 20) // Add some spacing around the plus button


                TabBarButton(
                    icon: "Groups", // Changed to asset name
                    isSelected: selectedTab == .groups
                ) { selectedTab = .groups }

                TabBarButton(
                    icon: "Profile", // Changed to asset name
                    isSelected: selectedTab == .profile
                ) { selectedTab = .profile }
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) { 
                Image(icon) // Using asset image name
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 30, height: 30) // Increased icon size
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

    var body: some View {
        Button(action: {
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

// Break out the button
struct ParseButtonView: View {
    var isLoading: Bool
    var isEmpty: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "play.card")
                        .font(.system(size: 17, weight: .semibold))
                }
                
                Text(isLoading ? "Parsing..." : "Parse Hand")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 123/255, green: 255/255, blue: 99/255),
                        Color(red: 100/255, green: 230/255, blue: 85/255)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(isEmpty || isLoading ? 0.6 : 1)
            )
            .foregroundColor(.black)
            .cornerRadius(16)
            .shadow(color: Color(red: 123/255, green: 255/255, blue: 99/255), radius: 8, y: 2)
        }
        .disabled(isEmpty || isLoading)
        .padding(.vertical, 4)
    }
}

// Break out success view
struct ParseSuccessView: View {
    let parsedHand: ParsedHandHistory
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Successfully Parsed!")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    // Display small blind and big blind as stakes
                    Text("Stakes: $\(parsedHand.raw.gameInfo.smallBlind)/$\(parsedHand.raw.gameInfo.bigBlind)")
                        .foregroundColor(.white)
                    
                    // Show total pot amount
                    Text("Pot: $\(String(format: "%.2f", parsedHand.raw.pot.amount))")
                        .foregroundColor(.white)
                    
                    // Display number of players
                    Text("Players: \(parsedHand.raw.players.count)")
                        .foregroundColor(.white)
                    
                    // Display hero's seat if available
                    if let hero = parsedHand.raw.players.first(where: { $0.isHero }) {
                        Text("Your Position: Seat \(hero.seat)")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                    }
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .transition(.opacity)
    }
}

// Simplified AddHandView that uses manual entry instead of parsing
struct AddHandView: View {
    let userId: String
    var onDismiss: () -> Void
    @Environment(\.dismiss) var dismiss

    init(userId: String, onDismiss: @escaping () -> Void) {
        self.userId = userId
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                .ignoresSafeArea()
            
            Text("Groups Coming Soon")
                .foregroundColor(.white)
        }
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
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 110, height: 110)
                                        .foregroundColor(Color.green.opacity(0.5))
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
                                    
                                if let bio = profile.bio, !bio.isEmpty {
                                    Text(bio)
                                        .font(.system(size: 16))
                                        .foregroundColor(.white.opacity(0.85))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                        .padding(.top, 12)
                                }
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

struct ProfileEditView: View {
    @State var profile: UserProfile
    var onSave: (UserProfile) -> Void
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userService: UserService
    
    // Profile data
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var bio: String = ""
    @State private var favoriteGame: String = "NLH"
    @State private var location: String = ""
    
    // UI states
    @State private var selectedImage: UIImage? = nil
    @State private var showImagePicker = false
    @State private var imagePickerItem: PhotosPickerItem? = nil
    @State private var isUploading = false
    @State private var uploadError: String? = nil
    @State private var isAnimating = false
    @State private var activeField: ProfileField? = nil
    @State private var scrollOffset: CGFloat = 0
    
    // Delete account
    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String? = nil
    
    // Game options
    let gameOptions = ["NLH", "PLO", "Omaha", "Stud8", "Razz"]
    
    // Focus management
    enum ProfileField {
        case displayName, username, bio, location
    }
    
    var body: some View {
        ZStack {
            // Background
            Color(red: 18/255, green: 18/255, blue: 22/255)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom navigation bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(
                                Circle()
                                    .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                            )
                    }
                    
                    Spacer()
                    
                    Text("Edit Profile")
                        .font(.system(size: 18, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: saveProfile) {
                        if isUploading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 20, height: 20)
                        } else {
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold, design: .default))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        }
                    }
                    .disabled(isUploading || isDeleting)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile photo section
                        VStack(spacing: 16) {
                            ZStack {
                                // Profile image container
                                Circle()
                                    .fill(Color(red: 32/255, green: 34/255, blue: 38/255))
                                    .frame(width: 120, height: 120)
                                    .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 2)
                                
                                // Profile image
                                if let selectedImage = selectedImage {
                                    Image(uiImage: selectedImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 110, height: 110)
                                        .clipShape(Circle())
                                } else if let url = profile.avatarURL, !url.isEmpty, let imageURL = URL(string: url) {
                                    AsyncImage(url: imageURL) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                                .frame(width: 110, height: 110)
                                                .clipShape(Circle())
                                        } else if phase.error != nil {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 50, design: .default))
                                                .foregroundColor(.gray)
                                        } else {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                                        }
                                    }
                                    .frame(width: 110, height: 110)
                                } else {
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 50, design: .default))
                                        .foregroundColor(.gray)
                                }
                                
                                // Camera button overlay
                                PhotosPicker(selection: $imagePickerItem, matching: .images) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                                            .frame(width: 32, height: 32)
                                        
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 14, design: .default))
                                            .foregroundColor(.white)
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 2)
                                    )
                                }
                                .onChange(of: imagePickerItem) { newItem in
                                    loadTransferableImage(from: newItem)
                                }
                                .position(x: 85, y: 85)
                            }
                            
                            Text("Change Profile Photo")
                                .font(.system(size: 14, weight: .medium, design: .default))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                        }
                        .padding(.top, 16)
                        
                        // Form fields
                        VStack(spacing: 20) {
                            // Display name field
                            ProfileTextField(
                                title: "DISPLAY NAME",
                                placeholder: "Your display name",
                                text: $displayName,
                                isActive: activeField == .displayName,
                                onEditingChanged: { isEditing in
                                    activeField = isEditing ? .displayName : nil
                                }
                            )
                            
                            // Username field (non-editable)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("USERNAME")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                
                                HStack {
                                    Text("@\(username)")
                                        .font(.system(size: 16, design: .default))
                                        .foregroundColor(.gray)
                                        .padding()
                                    
                                    Spacer()
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color.white.opacity(0.1),
                                                    Color.clear,
                                                    Color.clear,
                                                    Color.clear
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 1
                                        )
                                )
                            }
                            
                            // Bio field
                            ProfileTextField(
                                title: "BIO",
                                placeholder: "Tell us about yourself",
                                text: $bio,
                                isActive: activeField == .bio,
                                onEditingChanged: { isEditing in
                                    activeField = isEditing ? .bio : nil
                                }
                            )
                            
                            // Location field
                            ProfileTextField(
                                title: "LOCATION",
                                placeholder: "Your location",
                                text: $location,
                                isActive: activeField == .location,
                                onEditingChanged: { isEditing in
                                    activeField = isEditing ? .location : nil
                                }
                            )
                            
                            // Favorite game picker
                            VStack(alignment: .leading, spacing: 10) {
                                Text("FAVORITE GAME")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                
                                // Game selection cards
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(gameOptions, id: \.self) { game in
                                            Button(action: {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    favoriteGame = game
                                                }
                                            }) {
                                                Text(game)
                                                    .font(.system(size: 15, weight: favoriteGame == game ? .semibold : .medium, design: .default))
                                                    .foregroundColor(favoriteGame == game ? .black : .white)
                                                    .padding(.horizontal, 20)
                                                    .padding(.vertical, 12)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .fill(favoriteGame == game ?
                                                                  Color(red: 123/255, green: 255/255, blue: 99/255) :
                                                                  Color(red: 32/255, green: 35/255, blue: 40/255))
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 12)
                                                            .stroke(
                                                                favoriteGame == game ?
                                                                Color.clear :
                                                                Color.white.opacity(0.1),
                                                                lineWidth: 1
                                                            )
                                                    )
                                            }
                                            .buttonStyle(ScaleButtonStyle())
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Error message
                        if let uploadError = uploadError {
                            Text(uploadError)
                                .font(.system(size: 14, design: .default))
                                .foregroundColor(.red)
                                .padding(.top, 8)
                        }
                        
                        // Delete account button
                        VStack(spacing: 10) {
                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.top, 20)
                            
                            Button(action: { showDeleteConfirmation = true }) {
                                HStack {
                                    Spacer()
                                    Text("Delete Account")
                                        .font(.system(size: 15, weight: .medium, design: .default))
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(.vertical, 16)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .onAppear {
            initializeFields()
            animateIn()
        }
        .alert("Delete Your Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                showFinalDeleteConfirmation = true
            }
        } message: {
            Text("This will remove all your data from the app. This action cannot be undone.")
        }
        .alert("Permanently Delete Account", isPresented: $showFinalDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Yes, Delete Everything", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Are you absolutely sure? All your data, posts, groups, and messages will be permanently deleted.")
        }
        .alert("Error", isPresented: .init(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "An unknown error occurred")
        }
    }
    
    private func initializeFields() {
        displayName = profile.displayName ?? ""
        username = profile.username
        bio = profile.bio ?? ""
        favoriteGame = profile.favoriteGame ?? "NLH"
        location = profile.location ?? ""
    }
    
    private func animateIn() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeOut(duration: 0.4)) {
                isAnimating = true
            }
        }
    }
    
    private func loadTransferableImage(from imageSelection: PhotosPickerItem?) {
        guard let imageSelection = imageSelection else { return }
        
        Task {
            do {
                if let data = try await imageSelection.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            } catch {
                print("Error loading image: \(error)")
            }
        }
    }
    
    private func saveProfile() {
        // Update the profile with edited values
        var updatedProfile = profile
        updatedProfile.displayName = displayName.isEmpty ? nil : displayName
        updatedProfile.username = username
        updatedProfile.bio = bio.isEmpty ? nil : bio
        updatedProfile.favoriteGame = favoriteGame
        updatedProfile.location = location.isEmpty ? nil : location
        
        // Handle image upload if needed
        if let selectedImage = selectedImage {
            isUploading = true
            uploadError = nil
            
            userService.uploadProfileImage(selectedImage, userId: profile.id) { result in
                DispatchQueue.main.async {
                    isUploading = false
                    switch result {
                    case .success(let urlString):
                        updatedProfile.avatarURL = urlString
                        saveProfileToFirestore(updatedProfile)
                    case .failure(let error):
                        uploadError = "Image upload error: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            saveProfileToFirestore(updatedProfile)
        }
    }
    
    private func saveProfileToFirestore(_ updatedProfile: UserProfile) {
        Task {
            do {
                try await userService.updateUserProfile([
                    "displayName": updatedProfile.displayName ?? "",
                    "username": updatedProfile.username,
                    "bio": updatedProfile.bio ?? "",
                    "favoriteGame": updatedProfile.favoriteGame ?? "NLH",
                    "location": updatedProfile.location ?? "",
                    "avatarURL": updatedProfile.avatarURL ?? ""
                ])
                
                await MainActor.run {
                    onSave(updatedProfile)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    uploadError = "Failed to save profile: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteAccount() {
        guard let userId = Auth.auth().currentUser?.uid else {
            deleteError = "Not signed in"
            return
        }
        
        isDeleting = true
        
        Task {
            do {
                // 1. Delete user data from collections
                try await deleteUserDataFromFirestore(userId)
                
                // 2. Delete Firebase Auth user
                try await Auth.auth().currentUser?.delete()
                
                // 3. Sign out immediately after successful deletion
                do {
                    try Auth.auth().signOut()
                } catch {
                    print("Error signing out after account deletion: \(error.localizedDescription)")
                }
                
                await MainActor.run {
                    isDeleting = false
                    // The app will automatically redirect to the sign-in page due to auth state change
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    deleteError = "Failed to delete account: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func deleteUserDataFromFirestore(_ userId: String) async throws {
        let db = Firestore.firestore()
        let batch = db.batch()
        
        // Delete user document
        batch.deleteDocument(db.collection("users").document(userId))
        
        // Delete user's groups
        let userGroups = try await db.collection("users")
            .document(userId)
            .collection("groups")
            .getDocuments()
        
        for doc in userGroups.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete user's group invites
        let userInvites = try await db.collection("users")
            .document(userId)
            .collection("groupInvites")
            .getDocuments()
        
        for doc in userInvites.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete user's followers/following
        let followers = try await db.collection("users")
            .document(userId)
            .collection("followers")
            .getDocuments()
        
        for doc in followers.documents {
            batch.deleteDocument(doc.reference)
        }
        
        let following = try await db.collection("users")
            .document(userId)
            .collection("following")
            .getDocuments()
        
        for doc in following.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Commit the batch deletion of Firestore data
        try await batch.commit()
        
        // Attempt to delete profile image, but don't let it stop the account deletion process
        do {
            try await Storage.storage().reference()
                .child("profile_images/\(userId).jpg")
                .delete()
        } catch {
            // Log the error but continue with account deletion
            print("Profile image deletion failed: \(error.localizedDescription). Continuing with account deletion.")
        }
    }
}

// MARK: - Supporting Views

struct ProfileTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isActive: Bool
    let onEditingChanged: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
            
            TextField(placeholder, text: $text, onEditingChanged: onEditingChanged)
                .font(.system(size: 16, design: .default))
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isActive ?
                            LinearGradient(
                                gradient: Gradient(colors: [Color(red: 123/255, green: 255/255, blue: 99/255)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ) :
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.1),
                                    Color.clear,
                                    Color.clear,
                                    Color.clear
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isActive ? 1.5 : 1
                        )
                )
                .animation(.easeOut(duration: 0.2), value: isActive)
        }
    }
}

struct ProfileTextEditor: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isActive: Bool
    let onEditingChanged: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
            
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 16, design: .default))
                        .foregroundColor(.gray.opacity(0.7))
                        .padding(.top, 16)
                        .padding(.leading, 16)
                }
                
                TextEditor(text: $text)
                    .font(.system(size: 16, design: .default))
                    .foregroundColor(.white)
                    .frame(minHeight: 100)
                    .padding(4)
                    .background(Color.clear)
                    .onTapGesture {
                        onEditingChanged(true)
                    }
                    .onAppear {
                        UITextView.appearance().backgroundColor = .clear
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isActive ?
                        LinearGradient(
                            gradient: Gradient(colors: [Color(red: 123/255, green: 255/255, blue: 99/255)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ) :
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.1),
                                Color.clear,
                                Color.clear,
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isActive ? 1.5 : 1
                    )
            )
            .frame(height: 120)
            .animation(.easeOut(duration: 0.2), value: isActive)
        }
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
                    print("Error loading image: \(error)")
                    self.error = error
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    print("Invalid response")
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
    @State private var showHandInput = false
    @Binding var showSessionForm: Bool
    @Binding var showingLiveSession: Bool
    @Binding var showingOpenHomeGameFlow: Bool

    var body: some View {
        ZStack {
            // Dark background overlay
            if showingMenu {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        closeMenu()
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
                            
                            Button(action: closeMenu) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(Color(white: 0.7))
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                            .padding(.trailing, 20)
                        }
                        
                        VStack(spacing: 16) {
                            // Home Game button
                            MenuRow(
                                icon: "house.fill",
                                title: "Home Game",
                                action: {
                                    withAnimation(nil) {
                                        showingOpenHomeGameFlow = true
                                        showingMenu = false
                                    }
                                }
                            )
                            
                            // Past Session button
                            MenuRow(
                                icon: "clock.arrow.circlepath",
                                title: "Past Session",
                                action: {
                                    withAnimation(nil) {
                                        showSessionForm = true
                                        showingMenu = false
                                    }
                                }
                            )
                            
                            // Live Session button
                            MenuRow(
                                icon: "clock",
                                title: "Live Session",
                                action: {
                                    withAnimation(nil) {
                                        showingLiveSession = true
                                        showingMenu = false
                                    }
                                }
                            )
                            
                            // Add Hand button
                            MenuRow(
                                icon: "doc.text",
                                title: "Add Hand",
                                action: { 
                                    showHandInput = true 
                                    showingMenu = false
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
            }
        }
        .sheet(isPresented: $showHandInput) {
            NewHandEntryView()
        }
    }
    
    private func closeMenu() {
        withAnimation(.easeOut(duration: 0.2)) {
            showingMenu = false
        }
    }
}

// Menu row that exactly matches the screenshot
struct MenuRow: View {
    let icon: String
    let title: String
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

// Add Color hex extension if it doesn't exist
extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

// Sleek, modern HandInputView
struct HandInputViewSleek: View {
    let userId: String
    var onDismiss: () -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var handStore = HandStore(userId: "")
    @State private var handText = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingHandEntryWizard = false

    init(userId: String, onDismiss: @escaping () -> Void) {
        self.userId = userId
        self.onDismiss = onDismiss
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }

    var body: some View {
        ZStack {
            Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
            VStack(spacing: 24) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.7))
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding(.leading, 16)
                    
                    Spacer()
                    
                    Text("Add Poker Hand")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(white: 0.92))
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 36, height: 36)
                        .padding(.trailing, 16)
                }
                .padding(.top, 12)
                
                VStack(spacing: 20) {
                    Button(action: {
                        showingHandEntryWizard = true
                    }) {
                        HStack {
                            Image(systemName: "plus.square.fill")
                                .font(.system(size: 20))
                            Text("Create New Hand")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .foregroundColor(.black)
                        .background(
                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.green.opacity(0.10), radius: 6, y: 1)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(UIColor(red: 18/255, green: 19/255, blue: 22/255, alpha: 0.98)))
                )
                .padding(.horizontal, 16)
                
                Spacer()
            }
        }
        .onDisappear {
            // Call dismiss callback when view disappears
            onDismiss()
        }
    }
}


struct HandInputView: View {
    let userId: String
    var onDismiss: () -> Void
    @Environment(\.dismiss) var dismiss
    @StateObject private var handStore = HandStore(userId: "")
    @State private var handText = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingHandEntryWizard = false

    init(userId: String, onDismiss: @escaping () -> Void) {
        self.userId = userId
        self.onDismiss = onDismiss
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }

    var body: some View {
        // Implementation of HandInputView
        Text("Hand Input View")
    }
} 
