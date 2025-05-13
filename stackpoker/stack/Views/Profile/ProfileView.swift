import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Charts
import UIKit

// A transparent navigation container that provides navigation context without UI side effects
struct TransparentNavigationView<Content: View>: UIViewControllerRepresentable {
    var content: Content
    
    func makeUIViewController(context: Context) -> UIViewController {
        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear // Essential for transparency
        
        let navigationController = UINavigationController(rootViewController: hostingController)
        navigationController.navigationBar.isHidden = true // Hide the navigation bar
        navigationController.view.backgroundColor = .clear // Make container transparent
        
        // Ensure the background is truly transparent
        navigationController.navigationBar.setBackgroundImage(UIImage(), for: .default)
        navigationController.navigationBar.shadowImage = UIImage()
        navigationController.navigationBar.isTranslucent = true
        
        return navigationController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        if let navigationController = uiViewController as? UINavigationController,
           let hostingController = navigationController.viewControllers.first as? UIHostingController<Content> {
            hostingController.rootView = content
        }
    }
}

struct ProfileView: View {
    let userId: String
    @EnvironmentObject private var userService: UserService
    @StateObject private var sessionStore: SessionStore // Keep for analytics data
    @StateObject private var handStore: HandStore     // Keep for analytics data
    @EnvironmentObject private var postService: PostService // Added for recent activity
    @State private var showEdit = false // State for showing edit profile sheet
    
    @State private var selectedView: ProfileViewType = .profile
    @State private var selectedTimeRange = 1 // Default to 1W (index 1) for Analytics
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"]
    
    init(userId: String) {
        self.userId = userId
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }
    
    enum ProfileViewType {
        case profile
        case analytics
        case hands
        case sessions
        case settings
    }
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation buttons - padding adjusted to respect safe area
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        NavigationButton(
                            icon: "person.fill",
                            title: "Profile",
                            isSelected: selectedView == .profile,
                            action: { selectedView = .profile }
                        )
                        
                        NavigationButton(
                            icon: "chart.bar.fill",
                            title: "Analytics",
                            isSelected: selectedView == .analytics,
                            action: { selectedView = .analytics }
                        )
                        
                        NavigationButton(
                            icon: "doc.text.fill",
                            title: "Hands",
                            isSelected: selectedView == .hands,
                            action: { selectedView = .hands }
                        )
                        
                        NavigationButton(
                            icon: "clock.fill",
                            title: "Sessions",
                            isSelected: selectedView == .sessions,
                            action: { selectedView = .sessions }
                        )
                        
                        NavigationButton(
                            icon: "gearshape.fill",
                            title: "Settings",
                            isSelected: selectedView == .settings,
                            action: { selectedView = .settings }
                        )
                    }
                    .padding(.horizontal, 20)
                    // This padding will be applied correctly within the safe area context
                    .padding(.top) // Use default system padding for the top
                    .padding(.bottom, 16)
                }
                
                // Content based on selected view
                Group {
                    if selectedView == .profile {
                        ProfileContent(userId: userId, showEdit: $showEdit)
                    } else if selectedView == .analytics {
                        ZStack {
                            AppBackgroundView()
                                .ignoresSafeArea()
                            ScrollView {
                                VStack(spacing: 4) {
                                    IntegratedChartSection(
                                        selectedTimeRange: $selectedTimeRange,
                                        timeRanges: timeRanges,
                                        sessions: sessionStore.sessions,
                                        totalProfit: totalBankroll,
                                        timeRangeProfit: selectedTimeRangeProfit
                                    )
                                    .padding(.top, 6)
                                    .padding(.bottom, 2)
                                    
                                    EnhancedStatsCardGrid(
                                        winRate: winRate,
                                        averageProfit: averageProfit,
                                        totalSessions: totalSessions,
                                        bestSession: bestSession
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 16)
                                }
                                .padding(.bottom, 90)
                            }
                        }
                        .onAppear {
                            sessionStore.fetchSessions() // Ensure sessions are fetched for analytics
                        }
                    } else if selectedView == .hands {
                        ZStack {
                            AppBackgroundView()
                                .ignoresSafeArea()
                            HandsTab(handStore: handStore)
                        }
                        .disabled(false)
                        .allowsHitTesting(true)
                    } else if selectedView == .sessions {
                        ZStack {
                            AppBackgroundView()
                                .ignoresSafeArea()
                                
                            // Use the transparent navigation container 
                            TransparentNavigationView(content: 
                                SessionsTab(sessionStore: sessionStore)
                            )
                        }
                        .disabled(false)
                        .allowsHitTesting(true)
                    } else if selectedView == .settings {
                        SettingsView(userId: userId)
                    }
                }
                .id(selectedView)
            }
        }
        .navigationBarHidden(true)
        // Pass down environment objects that might be needed by sub-views like SettingsView or ProfileScreen
        .environmentObject(userService) 
        .environmentObject(postService)
        .environmentObject(sessionStore) 
        .environmentObject(handStore)
        .sheet(isPresented: $showEdit) { // Apply sheet modifier here in ProfileView
            if let profile = userService.currentUserProfile {
                // Assuming ProfileEditView is accessible (defined in the same module or correctly imported)
                ProfileEditView(profile: profile) { updatedProfile in
                    // Handle profile update if needed, e.g., refresh userService
                    Task { try? await userService.fetchUserProfile() } // Example: Refresh profile
                }
            }
        }
    }
    
    // MARK: - Analytics Helper Properties (Copied from previous working version)
    private var totalBankroll: Double {
        return sessionStore.sessions.reduce(0) { $0 + $1.profit }
    }
    
    private var selectedTimeRangeProfit: Double {
        let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
        return filteredSessions.reduce(0) { $0 + $1.profit }
    }
    
    private func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return sessionStore.sessions.filter { $0.startDate >= oneYearAgo }
        default: // All
            return sessionStore.sessions
        }
    }
    
    private var winRate: Double {
        let totalSessions = sessionStore.sessions.count
        if totalSessions == 0 { return 0 }
        let winningSessions = sessionStore.sessions.filter { $0.profit > 0 }.count
        return Double(winningSessions) / Double(totalSessions) * 100
    }
    
    private var averageProfit: Double {
        let totalSessions = sessionStore.sessions.count
        if totalSessions == 0 { return 0 }
        return totalBankroll / Double(totalSessions)
    }
    
    private var totalSessions: Int {
        return sessionStore.sessions.count
    }
    
    private var bestSession: (profit: Double, id: String)? {
        if let best = sessionStore.sessions.max(by: { $0.profit < $1.profit }) {
            return (best.profit, best.id)
        }
        return nil
    }
}

// This struct remains inside ProfileView.swift or is accessible to it
struct ProfileContent: View {
    let userId: String
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var postService: PostService // For accessing posts
    @State private var userPosts: [Post] = []
    @Binding var showEdit: Bool // Add Binding for showEdit

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let profile = userService.currentUserProfile {
                    VStack(alignment: .leading, spacing: 15) {
                        // Top Section: Avatar, Name, Username, Location, Stats
                        HStack(spacing: 16) {
                            // Smaller profile picture
                            if let url = profile.avatarURL, let imageURL = URL(string: url) {
                                AsyncImage(url: imageURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60) // Significantly smaller
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                    } else { placeholderAvatar(size: 60) }
                                }
                            } else { placeholderAvatar(size: 60) }
                            
                            // Middle: Name, Username, Location
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName ?? "@\(profile.username)")
                                    .font(.system(size: 20, weight: .bold)) // Slightly smaller
                                    .foregroundColor(.white)
                                if profile.displayName != nil {
                                    Text("@\(profile.username)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                if let location = profile.location, !location.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                        Text(location)
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Right: Stats for Followers/Following
                            VStack(alignment: .trailing, spacing: 4) {
                                HStack(spacing: 2) {
                                    Text("\(profile.followersCount)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("followers")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                HStack(spacing: 2) {
                                    Text("\(profile.followingCount)")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("following")
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            }
                        }

                        // Bio and Edit Profile button
                        HStack(alignment: .bottom) {
                            if let bio = profile.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Spacer()
                            }
                            
                            Button(action: {
                                showEdit = true
                            }) {
                                Text("Edit Profile")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                            .shadow(color: Color.green.opacity(0.3), radius: 3, y: 2)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    )
                    .padding(.horizontal, 16)
                } else {
                    // Loading state
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                        Text("Loading profile...")
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                    .onAppear { Task { try? await userService.fetchUserProfile() } }
                }
                
                // Recent activity section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recent Activity")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                    
                    if userPosts.isEmpty {
                        Text("No recent posts to display.")
                            .font(.system(size: 16))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                            .background(Color.black.opacity(0.15).cornerRadius(12))
                            .padding(.horizontal, 16)
                    } else {
                        // Production version based on working diagnostic approach
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(userPosts.prefix(5)) { post in 
                                    PostView(
                                        post: post,
                                        onLike: { Task { try? await postService.toggleLike(postId: post.id ?? "", userId: userService.currentUserProfile?.id ?? "") } },
                                        onComment: { /* Comment action */ },
                                        userId: userService.currentUserProfile?.id ?? ""
                                    )
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(10)
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
                .padding(.top, 10)
                .onAppear {
                    fetchUserPosts()
                }
            }
            .padding(.vertical, 20)
            .padding(.bottom, 100) // Extra padding for tab bar
        }
        // .sheet modifier will be moved to ProfileView
    }
    
    private func fetchUserPosts() {
        print("[ProfileView] Fetching posts for userId: \(userId)")
        Task {
            do {
                let fetchedPosts = try await postService.fetchPosts(forUserId: userId)
                print("[ProfileView] Successfully fetched \(fetchedPosts.count) posts")
                
                // Update on main thread
                await MainActor.run {
                    self.userPosts = fetchedPosts
                }
            } catch {
                print("[ProfileView] Error fetching posts: \(error)")
                self.userPosts = [] // Clear posts on error
            }
        }
    }
    
    // Helper for placeholder avatar
    @ViewBuilder
    private func placeholderAvatar(size: CGFloat) -> some View {
        Circle().fill(Color.gray.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "person.fill").foregroundColor(.gray).font(.system(size: size * 0.4)))
            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }
}

// Basic PostRow view (customize as needed)
struct PostRow: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading) {
            Text(post.content)
                .font(.body)
                .foregroundColor(.white)
            if let firstImageUrl = post.imageURLs?.first, let url = URL(string: firstImageUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                    } else if phase.error != nil {
                        Text("Could not load image")
                            .foregroundColor(.gray)
                    } else {
                        ProgressView()
                            .frame(height: 200) // Placeholder height
                    }
                }
            }
            Text("Posted on: \(post.createdAt, style: .date)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }
}

struct NavigationButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? 
                              Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                              Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                        .frame(width: 50, height: 50)
                        .shadow(color: isSelected ? Color.green.opacity(0.2) : Color.black.opacity(0.1),
                                radius: 4, y: 2)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .black : .white.opacity(0.8))
                }
                
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? 
                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                    .white.opacity(0.8))
            }
            .frame(width: 70)
            .padding(.vertical, 6)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }
}

struct SettingsView: View {
    let userId: String
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                // Settings Groups
                SettingsGroup(title: "Account") {
                    SettingsRow(icon: "person.fill", title: "Account Information")
                    SettingsRow(icon: "bell.fill", title: "Notifications")
                    SettingsRow(icon: "lock.fill", title: "Privacy & Security")
                }
                
                SettingsGroup(title: "App Settings") {
                    SettingsRow(icon: "display", title: "Appearance")
                    SettingsRow(icon: "hand.raised.fill", title: "Hand History Format")
                    SettingsRow(icon: "dollarsign.circle.fill", title: "Currency Settings")
                }
                
                SettingsGroup(title: "Support") {
                    SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support")
                    SettingsRow(icon: "exclamationmark.bubble.fill", title: "Report a Problem")
                    SettingsRow(icon: "hand.thumbsup.fill", title: "Rate the App")
                }
                
                // Sign Out Button
                Button(action: signOut) {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Delete Account Button
                Button(action: {}) {
                    HStack {
                        Spacer()
                        Text("Delete Account")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100) // Extra padding for tab bar
            }
        }
    }
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
            authViewModel.checkAuthState()
        } catch {
            print("Error signing out: \(error)")
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                .padding(.leading, 20)
            
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 1.0)))
            )
            .padding(.horizontal, 20)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    
    var body: some View {
        Button(action: {}) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
        }
        .buttonStyle(PlainButtonStyle())
    }
}



