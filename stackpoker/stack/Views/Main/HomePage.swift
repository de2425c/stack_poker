import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import PhotosUI
import UIKit

struct HomePage: View {
    @State private var selectedTab: Tab = .dashboard
    let userId: String
    @State private var showingMenu = false
    @State private var showingReplay = false
    @State private var replayHand: ParsedHandHistory?
    @State private var showingSessionForm = false
    @State private var showingLiveSession = false
    @State private var liveSessionBarExpanded = false
    @StateObject private var sessionStore: SessionStore
    @StateObject private var handStore: HandStore
    @StateObject private var postService = PostService()
    @EnvironmentObject private var userService: UserService
    
    init(userId: String) {
        self.userId = userId
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }
    
    enum Tab {
        case dashboard
        case feed
        case add
        case groups
        case profile
    }
    
    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                DashboardView(userId: userId)
                    .tag(Tab.dashboard)
                
                FeedView()
                    .tag(Tab.feed)
                
                Color.clear
                    .tag(Tab.add)
                
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
            }
            .compositingGroup() // Ensures the blendMode works properly
            
            // Dim overlay to darken screen outside the menu
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showingMenu = false }
                }
            
            // Main view structure
            VStack(spacing: 0) {
                // Live session bar (if active)
                if sessionStore.showLiveSessionBar && !sessionStore.liveSession.isEnded {
                    LiveSessionBar(
                        sessionStore: sessionStore,
                        isExpanded: $liveSessionBarExpanded,
                        onTap: { showingLiveSession = true }
                    )
                }
                
                // Main content
                TabView(selection: $selectedTab) {
                    DashboardView(userId: userId)
                        .tag(Tab.dashboard)
                    
                    FeedView(userId: userId)
                        .tag(Tab.feed)
                    
                    Color.clear // Placeholder for Add tab
                        .tag(Tab.add)
                    
                    GroupsView()
                        .environmentObject(userService)
                        .environmentObject(handStore)
                        .environmentObject(sessionStore)
                        .environmentObject(postService)
                        .tag(Tab.groups)
                    
                    ProfileScreen(userId: userId)
                        .tag(Tab.profile)
                }
                .background(Color.clear)
                .toolbar(.hidden, for: .tabBar)
            }

            CustomTabBar(
                selectedTab: $selectedTab,
                userId: userId,
                showingMenu: $showingMenu
            )
            .frame(maxHeight: .infinity, alignment: .bottom)
            .opacity(showingReplay ? 0 : 1)
            
            if showingMenu {
                AddMenuOverlay(
                    showingMenu: $showingMenu,
                    userId: userId,
                    showSessionForm: $showingSessionForm
                )
                .zIndex(1)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(isPresented: $showingReplay) {
            if let hand = replayHand {
                HandReplayView(hand: hand)
            }
        }
        .sheet(isPresented: $showingSessionForm) {
            SessionFormView(userId: userId)
        }
        .onDisappear {
            // Remove observer when view disappears
            NotificationCenter.default.removeObserver(self)
        }
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: HomePage.Tab
    let userId: String
    @Binding var showingMenu: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Background
            Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0))
                .frame(height: 80)
                .overlay(
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black.opacity(0.2))
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                            .padding(.top, -12)
                        HStack(spacing: 0) {
                            TabBarButton(
                                icon: "Dashboard",
                                title: "Dashboard",
                                isSelected: selectedTab == .dashboard
                            ) { selectedTab = .dashboard }
                            TabBarButton(
                                icon: "Feed",
                                title: "Feed",
                                isSelected: selectedTab == .feed
                            ) { selectedTab = .feed }
                            Spacer(minLength: 0)
                            ZStack {
                                Color.clear.frame(width: 1, height: 1)
                                AddButton(userId: userId, showingMenu: $showingMenu)
                                    .offset(y: -18)
                            }
                            .frame(width: 80)
                            Spacer(minLength: 0)
                            TabBarButton(
                                icon: "Groups",
                                title: "Groups",
                                isSelected: selectedTab == .groups
                            ) { selectedTab = .groups }
                            TabBarButton(
                                icon: "Profile",
                                title: "Profile",
                                isSelected: selectedTab == .profile
                            ) { selectedTab = .profile }
                        }
                        .padding(.horizontal, 0)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                )
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .padding(.top, 2) // Move icon up a bit
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.top, -2) // Move text up a bit
            }
            .foregroundColor(isSelected ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .gray)
            .frame(maxWidth: .infinity)
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
                    .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3)), radius: 10)
                PlusIcon()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.black)
                    .rotationEffect(.degrees(showingMenu ? 45 : 0))
            }
        }
        .padding(.trailing, 12)
        .padding(.bottom, 5)
    }
}

struct PlusIcon: View {
    var body: some View {
        GeometryReader { geo in
            let lineWidth: CGFloat = geo.size.width * 0.13
            let length: CGFloat = geo.size.width
            ZStack {
                RoundedRectangle(cornerRadius: lineWidth/2)
                    .frame(width: lineWidth, height: length)
                RoundedRectangle(cornerRadius: lineWidth/2)
                    .frame(width: length, height: lineWidth)
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
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
                VStack(spacing: 0) {
                    // STACK logo at the top
                    HStack {
                        Spacer()
                        Text("STACK")
                            .font(.system(size: 48, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        
                        // Add sign out button to top right
                        Button(action: signOut) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 0.7)))
                                )
                        }
                        .padding(.trailing, 16)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 0)
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
        do {
            try Auth.auth().signOut()
            userService.currentUserProfile = nil // Clear the profile before state change
            authViewModel.checkAuthState()
        } catch {
            print("Error signing out: \(error)")
        }
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

// Scale animation button style
struct ScaleButtonStyle: ButtonStyle {
    let scaleAmount: CGFloat
    
    init(scaleAmount: CGFloat = 0.97) {
        self.scaleAmount = scaleAmount
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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

    var body: some View {
        ZStack {
            // Background that excludes the tab bar central button
            ZStack {
                // Full screen material blur
                Color.black.opacity(0.5)
                    .background(.thinMaterial)
                    .ignoresSafeArea()
                
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
            }
            .compositingGroup() // Ensures the blendMode works properly
            
            // Dim overlay to darken screen outside the menu
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showingMenu = false }
                }
            
            // Actual menu content
            GeometryReader { geo in
                VStack {
                    Spacer()
                    VStack(spacing: 32) {
                        SleekMenuButton(
                            icon: "clock.arrow.circlepath",
                            title: "Past Session",
                            action: {
                                withAnimation(nil) {
                                    showSessionForm = true
                                    showingMenu = false
                                }
                            }
                        )
                        SleekMenuButton(
                            icon: "clock",
                            title: "Live Session",
                            action: { showingMenu = false }
                        )
                        SleekMenuButton(
                            icon: "doc.text",
                            title: "Add Hand",
                            action: { showHandInput = true }
                        )
                        
                        // Spacer to push content up
                        Spacer()
                            .frame(height: geo.size.height * 0.15)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .sheet(isPresented: $showHandInput) {
            HandInputViewSleek(userId: userId) {
                showHandInput = false
                showingMenu = false
            }
        }
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
    @State private var parsedHand: ParsedHandHistory?
    @State private var showingSuccess = false
    @FocusState private var isFocused: Bool

    init(userId: String, onDismiss: @escaping () -> Void) {
        self.userId = userId
        self.onDismiss = onDismiss
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }

    var body: some View {
        ZStack {
            Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Add Poker Hand")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color(white: 0.92))
                    .padding(.top, 12)
                VStack(spacing: 0) {
                    TextEditor(text: $handText)
                        .focused($isFocused)
                        .foregroundColor(Color(white: 0.85))
                        .font(.system(size: 16, design: .monospaced))
                        .frame(minHeight: 140, maxHeight: 180)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isFocused ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.9)) : Color.clear, lineWidth: 1.5)
                        )
                        .animation(.easeInOut(duration: 0.2), value: isFocused)
                        .padding(.bottom, 10)
                    Button(action: parseHand) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                        } else {
                            Text("Parse Hand")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: handText.isEmpty || isLoading ? 0.5 : 1))
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.green.opacity(0.10), radius: 6, y: 1)
                    .disabled(handText.isEmpty || isLoading)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(UIColor(red: 18/255, green: 19/255, blue: 22/255, alpha: 0.98)))
                )
                .padding(.horizontal, 8)
                if let parsedHand = parsedHand {
                    ScrollView {
                        Text(String(describing: parsedHand))
                            .foregroundColor(Color(white: 0.85))
                            .font(.system(.body, design: .monospaced))
                            .padding()
                    }
                    .background(Color.black.opacity(0.18))
                    .cornerRadius(10)
                    .padding(.horizontal, 8)
                }
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        withAnimation { showingMenu = false }
                    }) {
                        Color.clear
                            .frame(width: 70, height: 70)
                    }
                    Spacer()
                }
                .padding(.bottom, 20)
            }
        }
        .transition(.opacity)
        .sheet(isPresented: $showHandInput) {
            AddHandView(userId: userId, onDismiss: { showHandInput = false; showingMenu = false })
        }
    }
} 
