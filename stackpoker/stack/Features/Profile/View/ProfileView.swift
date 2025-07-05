import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Charts
import UIKit
import UniformTypeIdentifiers
import SwiftUIReorderableForEach

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
    @EnvironmentObject private var tutorialManager: TutorialManager // Added TutorialManager
    @StateObject private var sessionStore: SessionStore
    @StateObject private var bankrollStore: BankrollStore
    @StateObject private var challengeService: ChallengeService
    @StateObject private var challengeProgressTracker: ChallengeProgressTracker
    @StateObject private var stakeService = StakeService() // Add StakeService
    @EnvironmentObject private var postService: PostService
    @State private var showEdit = false
    @State private var showSettings = false
    @State private var selectedPostForNavigation: Post? = nil
    @State private var showingBankrollSheet = false
    // @State private var showingPostDetailSheet: Bool = false // Kept if ActivityContentView still uses it, but focus is on NavigationLink
    
    // State for full-screen card views
    @State private var showActivityDetailView = false
    @State private var showAnalyticsDetailView = false
    // REMOVED: @State private var showHandsDetailView = false
    @State private var showSessionsDetailView = false
    @State private var showStakingDashboardView = false // New state for Staking Dashboard
    @State private var showChallengesDetailView = false // New state for Challenges Dashboard
    
            init(userId: String) {
        self.userId = userId
        let bankrollStore = BankrollStore(userId: userId)
        let sessionStore = SessionStore(userId: userId, bankrollStore: bankrollStore)
        let challengeService = ChallengeService(userId: userId, bankrollStore: bankrollStore)
        
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _bankrollStore = StateObject(wrappedValue: bankrollStore)
        _challengeService = StateObject(wrappedValue: challengeService)
        _challengeProgressTracker = StateObject(wrappedValue: ChallengeProgressTracker(challengeService: challengeService, sessionStore: sessionStore))
    }
    
    // Removed ProfileTab enum and tabItems
    
    var body: some View {
        // let selectedTabGreen = Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
        // let deselectedTabGray = Color.white.opacity(0.7)
        // let clearColor = Color.clear
        
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Top bar with title and settings button (scrolls with content)
                    HStack {
                        Text("Profile")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 8)
                    
                    // Profile Card
                    ProfileCardView(
                        userId: userId,
                        showEdit: $showEdit,
                        showingFollowersSheet: $showingFollowersSheet,
                        showingFollowingSheet: $showingFollowingSheet
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    
                    // Invisible NavigationLink for programmatic post navigation
                    if let postToNavigate = selectedPostForNavigation {
                        NavigationLink(
                            destination: PostDetailView(post: postToNavigate, userId: userId),
                            isActive: Binding<Bool>(
                                get: { selectedPostForNavigation?.id == postToNavigate.id },
                                set: { if !$0 { selectedPostForNavigation = nil } }
                            ),
                            label: { EmptyView() }
                        )
                        .hidden()
                        .frame(width: 0, height: 0)
                    }
                    
                    // Navigation cards / buttons
                    VStack(spacing: 16) {
                        // Recent Activity Card and Analytics Card side-by-side
                        HStack(alignment: .top, spacing: 13) {
                            compactNavigationCard(
                                title: "Activity",
                                iconName: "list.bullet.below.rectangle",
                                baseColor: Color.blue,
                                action: { showActivityDetailView = true }
                            ) {
                                Text("See your latest posts")
                            }
                            
                            compactNavigationCard(
                                title: "Analytics",
                                iconName: "chart.bar.xaxis",
                                baseColor: Color.green,
                                action: { showAnalyticsDetailView = true }
                            ) {
                                Text("Analyze your results")
                            }
                            .tutorialHighlight(isHighlighted: tutorialManager.currentStep == .profileOverview)
                        }
                        
                        // Sessions Card
                        navigationCard(
                            title: "Sessions (\(sessionStore.sessions.count))",
                            iconName: "list.star",
                            baseColor: Color.orange,
                            action: { showSessionsDetailView = true }
                        ) {
                            if let recentSession = sessionStore.mostRecentSession {
                                HStack(alignment: .top, spacing: 8) {
                                    Capsule()
                                        .fill(Color.orange.opacity(0.7))
                                        .frame(width: 3)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(recentSession.stakes)
                                                .font(.plusJakarta(.callout, weight: .semibold))
                                                .foregroundColor(.white.opacity(0.9))
                                            Text("•")
                                                .font(.plusJakarta(.caption2, weight: .light))
                                                .foregroundColor(.gray)
                                            Text(relativeDateFormatter(from: recentSession.startTime))
                                                .font(.plusJakarta(.caption2, weight: .medium))
                                                .foregroundColor(.gray)
                                        }
                                        HStack(spacing: 4) {
                                            if !recentSession.gameName.isEmpty {
                                                Text(recentSession.gameName)
                                                    .font(.plusJakarta(.footnote))
                                                    .foregroundColor(.white.opacity(0.7))
                                                Text("•")
                                                    .font(.plusJakarta(.footnote))
                                                    .foregroundColor(.white.opacity(0.5))
                                            }
                                            Text(recentSession.profit >= 0 ? "+\(formatCurrency(recentSession.profit))" : "\(formatCurrency(recentSession.profit))")
                                                .font(.plusJakarta(.footnote, weight: .semibold))
                                                .foregroundColor(recentSession.profit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                                        }
                                    }
                                }
                            } else {
                                Text("Analyze your sessions.")
                                    .font(.plusJakarta(.subheadline))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .tutorialHighlight(isHighlighted: tutorialManager.currentStep == .profileOverview)
                        
                        // Staking Dashboard Card (New)
                        navigationCard(
                            title: "Staking Dashboard",
                            iconName: "person.2.square.stack.fill",
                            baseColor: Color.cyan, // Or any color you prefer
                            action: { showStakingDashboardView = true }
                        ) {
                            Text("View and manage your stakes")
                                .font(.plusJakarta(.subheadline))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        .tutorialHighlight(isHighlighted: tutorialManager.currentStep == .profileOverview)
                        
                        // Challenges Dashboard Card (New)
                        navigationCard(
                            title: "Challenges (\(challengeService.activeChallenges.count))",
                            iconName: "trophy.fill",
                            baseColor: Color.pink,
                            action: { showChallengesDetailView = true }
                        ) {
                            if !challengeService.activeChallenges.isEmpty {
                                if let firstChallenge = challengeService.activeChallenges.first {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack(alignment: .top, spacing: 8) {
                                            Capsule()
                                                .fill(Color.pink.opacity(0.7))
                                                .frame(width: 3)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(firstChallenge.title)
                                                    .font(.plusJakarta(.callout, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.9))
                                                    .lineLimit(1)
                                                Text("\(Int(firstChallenge.progressPercentage))% complete")
                                                    .font(.plusJakarta(.caption2, weight: .medium))
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        // Removed mini progress bar to keep profile clean
                                        if challengeService.activeChallenges.count > 1 {
                                            Text("and \(challengeService.activeChallenges.count - 1) more active")
                                                .font(.plusJakarta(.footnote))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                }
                            } else {
                                Text("Set goals and track results")
                                    .font(.plusJakarta(.subheadline))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .tutorialHighlight(isHighlighted: tutorialManager.currentStep == .profileOverview)
                        
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120) // Extra space so last buttons clear the tab bar
                    .padding(.top, 3) // Added 3 points of top padding to the VStack of cards
                }
            }
        }
        // Removed .onChange(of: selectedTab)
        .sheet(isPresented: $showEdit) {
            if let profile = userService.currentUserProfile {
                ProfileEditView(profile: profile) { updatedProfile in
                    userService.currentUserProfile = updatedProfile
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(userId: userId)
        }
        // .sheet(isPresented: $showingPostDetailSheet) // This was for PostDetailView, now handled by NavigationLink in ActivityContentView
        .sheet(isPresented: $showingFollowersSheet) { // Ensure these are declared
            NavigationView {
                FollowListView(userId: userId, listType: .followers)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .sheet(isPresented: $showingFollowingSheet) { // Ensure these are declared
            NavigationView {
                FollowListView(userId: userId, listType: .following)
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
        .fullScreenCover(isPresented: $showActivityDetailView) {
            NavigationView {
                ActivityContentViewWrapper(
                    userId: userId,
                    selectedPostForNavigation: $selectedPostForNavigation
                )
                .navigationTitle("Recent Activity")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showActivityDetailView = false }) {
                            Image(systemName: "chevron.backward")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(AppBackgroundView().ignoresSafeArea(.all))
            .accentColor(.white)
            .environmentObject(userService)
            .environmentObject(postService)
        }
        .fullScreenCover(isPresented: $showAnalyticsDetailView) {
            NavigationView {
                AnalyticsView(
                    userId: userId,
                    sessionStore: sessionStore,
                    bankrollStore: bankrollStore,
                    showFilterButton: true
                )
                .navigationTitle("Analytics")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showAnalyticsDetailView = false }) {
                            Image(systemName: "chevron.backward")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(AppBackgroundView().ignoresSafeArea(.all))
            .accentColor(.white)
            .environmentObject(sessionStore)
            .environmentObject(userService)
        }
        // REMOVED: .fullScreenCover(isPresented: $showHandsDetailView)
        /*
         .fullScreenCover(isPresented: $showHandsDetailView) {
         NavigationView {
         ZStack {
         AppBackgroundView().ignoresSafeArea()
         HandsTab(handStore: handStore)
         .padding(.top, -35)
         }
         .navigationTitle("Hands")
         .navigationBarTitleDisplayMode(.inline)
         .toolbar {
         ToolbarItem(placement: .navigationBarLeading) {
         Button(action: { showHandsDetailView = false }) {
         Image(systemName: "chevron.backward")
         .foregroundColor(.white)
         }
         }
         }
         }
         .toolbarBackground(Color.clear, for: .navigationBar)
         .toolbarBackground(.visible, for: .navigationBar)
         .background(AppBackgroundView().ignoresSafeArea(.all))
         .accentColor(.white)
         .environmentObject(handStore)
         .environmentObject(userService)
         }
         */
        .fullScreenCover(isPresented: $showSessionsDetailView) {
            NavigationView {
                ZStack {
                    AppBackgroundView().ignoresSafeArea()
                    SessionsTab(sessionStore: sessionStore, bankrollStore: bankrollStore)
                        .padding(.top, -33)
                }
                .navigationTitle("Sessions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: { showSessionsDetailView = false }) {
                            Image(systemName: "chevron.backward")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(AppBackgroundView().ignoresSafeArea(.all))
            .accentColor(.white)
            .environmentObject(sessionStore)
            .environmentObject(userService)
        }
        .fullScreenCover(isPresented: $showStakingDashboardView) {
            NavigationView {
                StakingDashboardView()
                    .padding(.top, -30)
                    .navigationTitle("Staking Dashboard")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { showStakingDashboardView = false }) {
                                Image(systemName: "chevron.backward")
                                    .foregroundColor(.white)
                            }
                        }
                    }
            }
            // For iOS 16+ make the toolbar background effectively transparent
            .toolbarBackground(
                Color.clear, // Use a clear color to make it transparent
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            // This background on the NavigationView should then show through the transparent toolbar area
            .background(AppBackgroundView().ignoresSafeArea(.all))
            .accentColor(.white)
            .environmentObject(userService)
            .environmentObject(stakeService)
            .environmentObject(ManualStakerService())
        }
        .fullScreenCover(isPresented: $showChallengesDetailView) {
            NavigationView {
                ChallengeDashboardView(userId: userId)
                    .navigationTitle("Challenges")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: { showChallengesDetailView = false }) {
                                Image(systemName: "chevron.backward")
                                    .foregroundColor(.white)
                            }
                        }
                    }
            }
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(AppBackgroundView().ignoresSafeArea(.all))
            .accentColor(.white)
            .environmentObject(challengeService)
            .environmentObject(sessionStore)
            .environmentObject(userService)
            .environmentObject(challengeProgressTracker)
            // REMOVED: .environmentObject(handStore)
            .environmentObject(postService)
        }
        .navigationBarHidden(true)
        .environmentObject(userService)
        .environmentObject(postService)
        .environmentObject(sessionStore)
        // REMOVED: .environmentObject(handStore)
        .environmentObject(challengeService)
        .onAppear {            
            if userService.currentUserProfile == nil {
                Task { try? await userService.fetchUserProfile() }
            }
            // Fetch posts for Activity
            Task {
                // Fetch if posts are for a different user or empty
                if postService.posts.isEmpty || postService.posts.first?.userId != userId {
                    try await postService.fetchPosts(forUserId: userId)
                }
            }
            // Fetch sessions for Sessions card/view - only load if empty
            if sessionStore.sessions.isEmpty {
                sessionStore.loadSessionsForUI()
            }
        }
    }
    
    // State variables for ProfileCardView, if not already present
    @State private var showingFollowersSheet: Bool = false
    @State private var showingFollowingSheet: Bool = false
    
    // Helper for creating styled navigation cards
    @ViewBuilder
    private func navigationCard<PreviewContent: View>(
        title: String,
        iconName: String,
        baseColor: Color,
        action: @escaping () -> Void,
        @ViewBuilder previewContent: () -> PreviewContent
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(baseColor.opacity(0.9))
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    previewContent()
                        .font(.plusJakarta(.subheadline))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 12, trailing: 20))
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(baseColor.opacity(0.25), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: baseColor.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // NEW function for compact side-by-side cards
    @ViewBuilder
    private func compactNavigationCard<PreviewContent: View>(
        title: String,
        iconName: String,
        baseColor: Color,
        action: @escaping () -> Void,
        @ViewBuilder previewContent: () -> PreviewContent
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(baseColor.opacity(0.9))
                    .frame(width: 25)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    previewContent()
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
                
                Spacer(minLength: 0)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(EdgeInsets(top: 14, leading: 10, bottom: 12, trailing: 10))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(baseColor.opacity(0.25), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: baseColor.opacity(0.1), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity) // Ensure each card takes equal width
    }
    
    // MARK: - Utility Functions for ProfileView Display
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    // Helper function to format date relatively
    private func relativeDateFormatter(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated // e.g., "1h ago", "2d ago"
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// Wrapper for ActivityContentView to manage its own dismissal and title
struct ActivityContentViewWrapper: View {
    let userId: String
    @Binding var selectedPostForNavigation: Post?

    @EnvironmentObject private var userService: UserService 
    @EnvironmentObject private var postService: PostService

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()
            ActivityContentView(
                userId: userId,
                selectedPostForNavigation: $selectedPostForNavigation
            )
        }
        .navigationTitle("Recent Activity") 
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Button Styles
struct ScalePressButtonStyle: ButtonStyle {
    let scaleAmount: CGFloat = 0.95
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}






                
