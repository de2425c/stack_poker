import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Charts
import UIKit
import UniformTypeIdentifiers

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
    @StateObject private var sessionStore: SessionStore
    @StateObject private var handStore: HandStore
    @StateObject private var challengeService: ChallengeService
    @StateObject private var challengeProgressTracker: ChallengeProgressTracker
    @EnvironmentObject private var postService: PostService
    @State private var showEdit = false
    @State private var showSettings = false
    @State private var selectedPostForNavigation: Post? = nil
    // @State private var showingPostDetailSheet: Bool = false // Kept if ActivityContentView still uses it, but focus is on NavigationLink
    
    // State for full-screen card views
    @State private var showActivityDetailView = false
    @State private var showAnalyticsDetailView = false
    @State private var showHandsDetailView = false
    @State private var showSessionsDetailView = false
    @State private var showStakingDashboardView = false // New state for Staking Dashboard
    @State private var showChallengesDetailView = false // New state for Challenges Dashboard
    
    // Analytics specific state (remains for analyticsDetailContent)
    @State private var selectedTimeRange = 1 // Default to 1W (index 1) for Analytics
    @State private var selectedCarouselIndex = 0 // For carousel page selection
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"] // Used by analyticsDetailContent
    
    // Chart interaction states
    @State private var selectedDataPoint: (date: Date, profit: Double)? = nil
    @State private var touchLocation: CGPoint = .zero
    @State private var showTooltip: Bool = false
    
    init(userId: String) {
        self.userId = userId
        let sessionStore = SessionStore(userId: userId)
        let handStore = HandStore(userId: userId)
        let challengeService = ChallengeService(userId: userId)
        
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _handStore = StateObject(wrappedValue: handStore)
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
                        HStack(alignment: .top, spacing: 3) {
                            compactNavigationCard(
                                title: "Recent Activity",
                                iconName: "list.bullet.below.rectangle",
                                baseColor: Color.blue, 
                                action: { showActivityDetailView = true }
                            ) {
                                Text("View your latest posts.")
                            }
                            .frame(maxWidth: .infinity)

                            compactNavigationCard(
                                title: "Analytics",
                                iconName: "chart.bar.xaxis",
                                baseColor: Color.green, 
                                action: { showAnalyticsDetailView = true }
                            ) {
                                Text("Track your performance stats.")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, -4)

                        // Hands Card
                        navigationCard(
                            title: "Hands (\(handStore.savedHands.count))",
                            iconName: "suit.spade.fill",
                            baseColor: Color.purple, 
                            action: { showHandsDetailView = true }
                        ) {
                            if let recentHand = handStore.mostRecentHand {
                                HStack(alignment: .top, spacing: 8) {
                                    Capsule()
                                        .fill(Color.purple.opacity(0.7))
                                        .frame(width: 3)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(recentHand.heroPnL >= 0 ? "Won $\(Int(recentHand.heroPnL))" : "Lost $\(Int(abs(recentHand.heroPnL)))")
                                                .font(.plusJakarta(.callout, weight: .semibold))
                                                .foregroundColor(recentHand.heroPnL >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                                            Text("•")
                                                .font(.plusJakarta(.caption2, weight: .light))
                                                .foregroundColor(.gray)
                                            Text(relativeDateFormatter(from: recentHand.timestamp))
                                                .font(.plusJakarta(.caption2, weight: .medium))
                                                .foregroundColor(.gray)
                                        }
                                        Text(recentHand.handSummary)
                                            .font(.plusJakarta(.footnote))
                                            .foregroundColor(.white.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                            } else {
                                Text("Review your logged poker hands.")
                                    .font(.plusJakarta(.subheadline))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        
                        // Sessions Card
                        navigationCard(
                            title: "Sessions (\(totalSessions))",
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
                                Text("Manage and analyze your game sessions.")
                                    .font(.plusJakarta(.subheadline))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }

                        // Staking Dashboard Card (New)
                        navigationCard(
                            title: "Staking Dashboard",
                            iconName: "person.2.square.stack.fill",
                            baseColor: Color.cyan, // Or any color you prefer
                            action: { showStakingDashboardView = true }
                        ) {
                            Text("View and manage your stakes.")
                                .font(.plusJakarta(.subheadline))
                                .foregroundColor(.white.opacity(0.85))
                        }

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
                                Text("Set goals and track your poker journey.")
                                    .font(.plusJakarta(.subheadline))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }

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
                    Task { 
                        try? await userService.fetchUserProfile() 
                    }
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
                analyticsDetailContent()
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
        .fullScreenCover(isPresented: $showSessionsDetailView) {
            NavigationView {
                ZStack {
                    AppBackgroundView().ignoresSafeArea()
                    SessionsTab(sessionStore: sessionStore)
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
            .environmentObject(StakeService()) 
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
            .environmentObject(handStore)
            .environmentObject(postService)
        }
        .navigationBarHidden(true)
        .environmentObject(userService)
        .environmentObject(postService)
        .environmentObject(sessionStore)
        .environmentObject(handStore)
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

                } else {

                }
            }
            // Fetch sessions for Analytics & Sessions cards/views
            if sessionStore.sessions.isEmpty {

                sessionStore.fetchSessions()

            } else {

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
            ZStack { // Wrap content in ZStack for better centering when stretched
                // Background is applied below, to the ZStack i
            //tself or Button

                HStack(alignment: .center, spacing: 10) { // Explicit .center for items
                    Image(systemName: iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(baseColor.opacity(0.9))
                        .frame(width: 25)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        previewContent()
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .layoutPriority(1)
                    
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(EdgeInsets(top: 14, leading: 20, bottom: 12, trailing: 20))
                .frame(maxHeight: .infinity, alignment: .center) // ensure card stretches to full row height
            }
            .background( // Apply background to the ZStack (or Button)
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
    }
    
    // MARK: - Analytics Helper Properties (Unchanged, used by analyticsDetailContent)
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
    
    // MARK: - New Analytics Helper Properties
    private var totalHoursPlayed: Double {
        return sessionStore.sessions.reduce(0) { $0 + $1.hoursPlayed }
    }

    private var averageSessionLength: Double {
        if totalSessions == 0 { return 0 }
        return totalHoursPlayed / Double(totalSessions)
    }

    private var highestCashoutToBuyInRatio: (ratio: Double, session: Session)? {
        guard !sessionStore.sessions.isEmpty else { return nil }
        
        var maxRatio: Double = 0
        var sessionWithMaxRatio: Session? = nil
        
        for session in sessionStore.sessions {
            if session.buyIn > 0 { // Avoid division by zero
                let ratio = session.cashout / session.buyIn
                if ratio > maxRatio {
                    maxRatio = ratio
                    sessionWithMaxRatio = session
                }
            }
        }
        
        if let session = sessionWithMaxRatio {
            return (maxRatio, session)
        }
        return nil
    }

    enum TimeOfDayCategory: String, CaseIterable {
        case morning = "Morning Pro" // 5 AM - 12 PM
        case afternoon = "Afternoon Grinder" // 12 PM - 5 PM
        case evening = "Evening Shark" // 5 PM - 9 PM
        case night = "Night Owl" // 9 PM - 5 AM
        case unknown = "Versatile Player"

        var icon: String {
            switch self {
            case .morning: return "sun.max.fill"
            case .afternoon: return "cloud.sun.fill"
            case .evening: return "moon.stars.fill"
            case .night: return "zzz"
            case .unknown: return "questionmark.circle.fill"
            }
        }
    }

    private var pokerPersona: (category: TimeOfDayCategory, dominantHours: String) {
        guard !sessionStore.sessions.isEmpty else {
            return (.unknown, "N/A")
        }

        var morningSessions = 0 // 5 AM - 11:59 AM
        var afternoonSessions = 0 // 12 PM - 4:59 PM
        var eveningSessions = 0   // 5 PM - 8:59 PM
        var nightSessions = 0     // 9 PM - 4:59 AM

        let calendar = Calendar.current
        for session in sessionStore.sessions {
            let hour = calendar.component(.hour, from: session.startTime)
            switch hour {
            case 5..<12: morningSessions += 1
            case 12..<17: afternoonSessions += 1
            case 17..<21: eveningSessions += 1
            case 21..<24, 0..<5: nightSessions += 1
            default: break
            }
        }

        let counts = [
            "Morning": morningSessions,
            "Afternoon": afternoonSessions,
            "Evening": eveningSessions,
            "Night": nightSessions
        ]
        
        let totalPlaySessions = Double(morningSessions + afternoonSessions + eveningSessions + nightSessions)
        if totalPlaySessions == 0 { return (.unknown, "N/A")}

        var persona: TimeOfDayCategory = .unknown
        var maxCount = 0
        var dominantPeriodName = "N/A"

        if morningSessions > maxCount { maxCount = morningSessions; persona = .morning; dominantPeriodName = "Morning" }
        if afternoonSessions > maxCount { maxCount = afternoonSessions; persona = .afternoon; dominantPeriodName = "Afternoon"}
        if eveningSessions > maxCount { maxCount = eveningSessions; persona = .evening; dominantPeriodName = "Evening" }
        if nightSessions > maxCount { maxCount = nightSessions; persona = .night; dominantPeriodName = "Night"}
        
        let percentage = (Double(maxCount) / totalPlaySessions * 100)
        let dominantHoursString = "\(dominantPeriodName): \(String(format: "%.0f%%", percentage))"
        
        return (persona, dominantHoursString)
    }
    
    private var topLocation: (location: String, count: Int)? {
        guard !sessionStore.sessions.isEmpty else { return nil }
        
        // Consider gameName as a fallback if location is nil or empty
        let locationsFromSessions = sessionStore.sessions.map { session -> String? in
            let trimmedLocation = session.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let loc = trimmedLocation, !loc.isEmpty {
                return loc
            }
            let trimmedGameName = session.gameName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedGameName.isEmpty {
                return trimmedGameName // Use gameName as fallback
            }
            return nil
        }

        let validLocations = locationsFromSessions.compactMap { $0 }.filter { !$0.isEmpty }
        if validLocations.isEmpty { return nil }
        
        let locationCounts = validLocations.reduce(into: [:]) { counts, location in counts[location, default: 0] += 1 }
        
        if let (topLoc, count) = locationCounts.max(by: { $0.value < $1.value }) {
            return (topLoc, count)
        }
        return nil
    }
    
    private var carouselHighlights: [CarouselHighlight] {
        var items: [CarouselHighlight] = []

        // Top Location (Hot Spot) - FIRST
        if let locData = topLocation {
            items.append(CarouselHighlight(
                type: .location,
                title: "Hot Spot",
                iconName: "mappin.and.ellipse",
                primaryText: locData.location,
                secondaryText: "Played \(locData.count) times",
                tertiaryText: nil
            ))
        }

        // Best Multiplier
        if let ratioData = highestCashoutToBuyInRatio {
            items.append(CarouselHighlight(
                type: .multiplier,
                title: "Best Multiplier",
                iconName: "flame.fill",
                primaryText: String(format: "%.1fx", ratioData.ratio),
                secondaryText: "Buy-in: $\(Int(ratioData.session.buyIn).formattedWithCommas)",
                tertiaryText: "Cash-out: $\(Int(ratioData.session.cashout).formattedWithCommas)"
            ))
        }

        // Poker Persona
        items.append(CarouselHighlight(
            type: .persona,
            title: "Your Style",
            iconName: pokerPersona.category.icon,
            primaryText: pokerPersona.category.rawValue,
            secondaryText: pokerPersona.dominantHours,
            tertiaryText: nil
        ))

        return items.filter { !$0.primaryText.isEmpty || $0.type == .persona }
    }
    
    // Content for Analytics Detail View (extracted from old tabContent)
    @ViewBuilder
    private func analyticsDetailContent() -> some View {
        // This ScrollView will be part of the NavigationView in fullScreenCover
        ScrollView {
            VStack(spacing: 15) { // Reduced main spacing
                // Bankroll section with past month profit/loss indicator
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bankroll")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    // Show selected data point profit or total bankroll
                    Text(selectedDataPoint != nil ? 
                         "$\(Int(selectedDataPoint!.profit).formattedWithCommas)" : 
                         "$\(Int(totalBankroll).formattedWithCommas)")
                        .font(.system(size: selectedDataPoint != nil ? 40 : 36, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedDataPoint?.profit)
        
                    HStack(spacing: 4) {
                        if let selectedData = selectedDataPoint {
                            // Show selected date indicator
                            Image(systemName: selectedData.profit >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 10))
                                .foregroundColor(selectedData.profit >= 0 ? 
                                    Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                    Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                            
                            Text("at \(formatTooltipDate(selectedData.date))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(selectedData.profit >= 0 ? 
                                    Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                    Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                        } else {
                            // Show time range indicator (original)
                            let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
                            let timeRangeProfit = filteredSessions.reduce(0) { $0 + $1.profit }
                            
                            Image(systemName: timeRangeProfit >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                                .font(.system(size: 10))
                                .foregroundColor(timeRangeProfit >= 0 ? 
                                    Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                    Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                            
                            Text("$\(abs(Int(timeRangeProfit)).formattedWithCommas)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(timeRangeProfit >= 0 ? 
                                    Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                    Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                            
                            Text(getTimeRangeLabel(for: selectedTimeRange))
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedDataPoint != nil)
                }
                .padding(.horizontal, 20)
                
                // Chart display with time selectors at bottom
                VStack(spacing: 8) { // Reduced spacing
                    if sessionStore.sessions.isEmpty {
                        Text("No sessions recorded")
                            .foregroundColor(.gray)
                            .frame(height: 220)
                            .frame(maxWidth: .infinity) // Ensure it centers if no data
                    } else {
                        // Display chart using BankrollGraph
                        GeometryReader { geometry in
                            ZStack {
                                // Y-axis grid lines (subtle)
                                VStack(spacing: 0) {
                                    ForEach(0..<5) { _ in
                                        Spacer()
                                        Divider()
                                            .background(Color.gray.opacity(0.1))
                                    }
                                }
                                
                                // Beautiful background gradient overlay
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.clear, location: 0),
                                        .init(color: Color.white.opacity(0.02), location: 0.3),
                                        .init(color: Color.white.opacity(0.03), location: 0.7),
                                        .init(color: Color.clear, location: 1)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .blendMode(.overlay)
                                
                                // Simple line chart - use green or red based on profit/loss for the selected time range
                                let selectedSessions = filteredSessionsForTimeRange(selectedTimeRange)
                                let currentRangeProfit = selectedSessions.reduce(0) { $0 + $1.profit } // Renamed from selectedTimeRangeProfit to avoid conflict
                                let isProfit = currentRangeProfit >= 0
                                let chartColor = isProfit ? 
                                    Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                    Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
                                
                                // Simplified line chart
                                Path { path in
                                    let sessions = filteredSessionsForTimeRange(selectedTimeRange)
                                    
                                    guard !sessions.isEmpty else { return }
                                    
                                    var cumulativeProfit: [Double] = []
                                    var cumulative = 0.0
                                    
                                    for session in sessions.sorted(by: { $0.startDate < $1.startDate }) {
                                        cumulative += session.profit
                                        cumulativeProfit.append(cumulative)
                                    }
                                    
                                    guard !cumulativeProfit.isEmpty else { return }
                                    
                                    // Find the min/max for scaling
                                    let minProfit = cumulativeProfit.min() ?? 0
                                    let maxProfit = max(cumulativeProfit.max() ?? 1, 1) // Ensure maxProfit is at least 1 to avoid division by zero if range is 0
                                    let range = max(maxProfit - minProfit, 1) // Ensure range is at least 1
                                    
                                    // Draw the path
                                    let stepX = cumulativeProfit.count > 1 ? geometry.size.width / CGFloat(cumulativeProfit.count - 1) : geometry.size.width
                                    
                                    // Function to get Y position
                                    func getY(_ value: Double) -> CGFloat {
                                        let normalized = range == 0 ? 0.5 : (value - minProfit) / range // Handle range == 0 case
                                        return geometry.size.height * (1 - CGFloat(normalized))
                                    }
                                    
                                    // Start path
                                    path.move(to: CGPoint(x: 0, y: getY(cumulativeProfit[0])))
                                    
                                    // Draw lines to each point
                                    for i in 1..<cumulativeProfit.count {
                                        let x = CGFloat(i) * stepX
                                        let y = getY(cumulativeProfit[i])
                                        
                                        // Smooth curve
                                        if i > 0 {
                                            let prevX = CGFloat(i-1) * stepX
                                            let prevY = getY(cumulativeProfit[i-1])
                                            
                                            let controlPoint1 = CGPoint(x: prevX + stepX/3, y: prevY)
                                            let controlPoint2 = CGPoint(x: x - stepX/3, y: y)
                                            
                                            path.addCurve(to: CGPoint(x: x, y: y), 
                                                       control1: controlPoint1, 
                                                       control2: controlPoint2)
                                        }
                                    }
                                }
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            chartColor.opacity(0.9),
                                            chartColor,
                                            chartColor.opacity(0.95)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                                )
                                .shadow(color: chartColor.opacity(0.4), radius: 4, y: 2)
                                
                                // Add chart area fill with gradient
                                Path { path in
                                    let sessions = filteredSessionsForTimeRange(selectedTimeRange)
                                    
                                    guard !sessions.isEmpty else { return }
                                    
                                    var cumulativeProfit: [Double] = []
                                    var cumulative = 0.0
                                    
                                    for session in sessions.sorted(by: { $0.startDate < $1.startDate }) {
                                        cumulative += session.profit
                                        cumulativeProfit.append(cumulative)
                                    }
                                    
                                    guard !cumulativeProfit.isEmpty else { return }
                                    
                                    // Find the min/max for scaling
                                    let minProfit = cumulativeProfit.min() ?? 0
                                    let maxProfit = max(cumulativeProfit.max() ?? 1, 1)
                                    let range = max(maxProfit - minProfit, 1)
                                    
                                    // Draw the path
                                    let stepX = cumulativeProfit.count > 1 ? geometry.size.width / CGFloat(cumulativeProfit.count - 1) : geometry.size.width

                                    // Function to get Y position
                                    func getY(_ value: Double) -> CGFloat {
                                        let normalized = range == 0 ? 0.5 : (value - minProfit) / range
                                        return geometry.size.height * (1 - CGFloat(normalized))
                                    }
                                    
                                    // Start path - bottom left
                                    path.move(to: CGPoint(x: 0, y: geometry.size.height))
                                    
                                    // Bottom left to first data point
                                    path.addLine(to: CGPoint(x: 0, y: getY(cumulativeProfit[0])))
                                    
                                    // Draw curves through all points
                                    for i in 1..<cumulativeProfit.count {
                                        let x = CGFloat(i) * stepX
                                        let y = getY(cumulativeProfit[i])
                                        
                                        // Smooth curve
                                        if i > 0 {
                                            let prevX = CGFloat(i-1) * stepX
                                            let prevY = getY(cumulativeProfit[i-1])
                                            
                                            let controlPoint1 = CGPoint(x: prevX + stepX/3, y: prevY)
                                            let controlPoint2 = CGPoint(x: x - stepX/3, y: y)
                                            
                                            path.addCurve(to: CGPoint(x: x, y: y), 
                                                       control1: controlPoint1, 
                                                       control2: controlPoint2)
                                        }
                                    }
                                    
                                    // Last point to bottom right
                                    path.addLine(to: CGPoint(x: cumulativeProfit.count > 1 ? geometry.size.width : 0, y: geometry.size.height)) // Handle single point
                                    
                                    // Close the path
                                    path.closeSubpath()
                                }
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(stops: [
                                            .init(color: chartColor.opacity(0.35), location: 0),
                                            .init(color: chartColor.opacity(0.15), location: 0.4),
                                            .init(color: chartColor.opacity(0.08), location: 0.7),
                                            .init(color: Color.clear, location: 1)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                
                                // Interactive overlay for touch detection
                                Rectangle()
                                    .fill(Color.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                handleChartTouch(at: value.location, in: geometry)
                                            }
                                            .onEnded { _ in
                                                withAnimation(.easeOut(duration: 0.3)) {
                                                    showTooltip = false
                                                    selectedDataPoint = nil
                                                }
                                            }
                                    )
                                
                                // Unified touch indicator with line and dot
                                if showTooltip {
                                    // Vertical indicator line with gradient
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: Color.clear, location: 0),
                                                    .init(color: Color.white.opacity(0.6), location: 0.1),
                                                    .init(color: Color.white.opacity(0.8), location: 0.5),
                                                    .init(color: Color.white.opacity(0.6), location: 0.9),
                                                    .init(color: Color.clear, location: 1)
                                                ]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: 1)
                                        .position(x: touchLocation.x, y: geometry.size.height / 2)
                                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                }
                            }
                        }
                        .frame(height: 200) // Adjusted height for chart
                        
                        // Time period selector
                        HStack {
                            // Using self.timeRanges to refer to the ProfileView's property
                            ForEach(Array(self.timeRanges.enumerated()), id: \.element) { index, rangeString in
                                Button(action: {
                                    self.selectedTimeRange = index // Update ProfileView's @State
                                }) {
                                    Text(rangeString) // Display 24H, 1W, etc.
                                        .font(.system(size: 13, weight: self.selectedTimeRange == index ? .medium : .regular))
                                        .foregroundColor(self.selectedTimeRange == index ? .white : .gray)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8) // Make buttons easier to tap
                                        .background(self.selectedTimeRange == index ? Color.gray.opacity(0.3) : Color.clear)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 5) // Reduced top padding
                
                // Premium Highlights Carousel Section
                Text("HIGHLIGHTS")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12) // Slightly reduced spacing

                // HStack containing Carousel and Win Rate Wheel
                VStack(spacing: 8) {
                    // STEP 1: Calculate proper height based on screen width
                    // Formula: ~50pt padding + (6/3)y + y = screen_width = ~50pt + 3y
                    // Solving: y = (screen_width - 50) / 3
                    let screenWidth = UIScreen.main.bounds.width
                    let squareSize: CGFloat = (screenWidth - 50) / 3
                    
                    // STEP 2: Carousel width is 6/3 (=2) times the square size for 60% screen
                    let carouselWidth: CGFloat = 2.0 * squareSize
                    
                    // STEP 3: Carousel content height matches square size (excluding page indicators)
                    let carouselContentHeight: CGFloat = squareSize
                    
                    // Main content row - carousel and win rate with same height
                    HStack(spacing: 20) {
                        // Carousel content only (no page indicators)
                        TabView(selection: $selectedCarouselIndex) {
                            ForEach(carouselHighlights.indices, id: \.self) { index in
                                let highlight = carouselHighlights[index]
                                
                                VStack(alignment: .leading, spacing: 12) {
                                    // Header
                                    HStack(spacing: 10) {
                                        Image(systemName: highlight.iconName)
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(highlight.type == .multiplier ? .orange : (highlight.type == .persona ? .cyan : .pink))
                                            .frame(width: 28, height: 28)
                                        
                                        Text(highlight.title)
                                            .font(.system(size: 15, weight: .bold, design: .rounded))
                                            .foregroundColor(.white.opacity(0.9))
                                    
                                        Spacer()
                                    }
                                    
                                    // Primary content
                                    Text(highlight.primaryText)
                                        .font(.system(size: highlight.type == .multiplier ? 38 : 26, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    
                                    // Secondary and tertiary content - for multiplier, show buy-in and cashout adjacent
                                    if highlight.type == .multiplier {
                                        if let secondaryText = highlight.secondaryText, let tertiaryText = highlight.tertiaryText {
                                            HStack(spacing: 12) {
                                                Text(secondaryText)
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.75))
                                                Text(tertiaryText)
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundColor(.white.opacity(0.75))
                                            }
                                        }
                                    } else {
                                        // For other types, show normally
                                        if let secondaryText = highlight.secondaryText {
                                            Text(secondaryText)
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                                .foregroundColor(.white.opacity(0.75))
                                        }
                                        
                                        if let tertiaryText = highlight.tertiaryText {
                                            Text(tertiaryText)
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .foregroundColor(.white.opacity(0.65))
                                        }
                                    }
                                    
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .background(
                        ZStack {
                                        RoundedRectangle(cornerRadius: carouselContentHeight * 0.15)
                                            .fill(Material.ultraThinMaterial)
                                            .opacity(0.08) 
                                        
                                        RoundedRectangle(cornerRadius: carouselContentHeight * 0.15)
                                            .fill(Color.white.opacity(0.02))
                                        
                                        RoundedRectangle(cornerRadius: carouselContentHeight * 0.15)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.15),
                                                        Color.white.opacity(0.05),
                                                        Color.clear
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 0.7
                                            )
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: carouselContentHeight * 0.15))
                                .tag(index)
                            }
                        }
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                        .frame(width: carouselWidth, height: carouselContentHeight)
                        .clipShape(RoundedRectangle(cornerRadius: carouselContentHeight * 0.15))
                        
                        // Win-rate square (height = width = carousel height)
                        WinRateCard(winRate: winRate)
                            .frame(width: squareSize, height: squareSize)
                    }
                    
                    // Page indicators below the main content
                    if carouselHighlights.count > 1 {
                        HStack {
                            // Spacer to center indicators under carousel
                            HStack(spacing: 7) {
                                ForEach(carouselHighlights.indices, id: \.self) { index in
                                    Capsule()
                                        .fill(selectedCarouselIndex == index ? Color.white.opacity(0.85) : Color.white.opacity(0.3))
                                        .frame(width: selectedCarouselIndex == index ? 20 : 7, height: 7)
                                        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: selectedCarouselIndex)
                                }
                            }
                            .frame(width: carouselWidth)
                            
                            Spacer()
                        }
                    }
                }
                .frame(height: (UIScreen.main.bounds.width - 50) / 3 + 20) // Dynamic height + small buffer
                .padding(.horizontal, 20)
                .padding(.bottom, 0)

                // Slim Performance lines (no boxes)
                Text("PERFORMANCE STATS")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.gray.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                    performanceLine(icon: "dollarsign.circle.fill", color: .green, title: "Avg. Profit", value: "$\(Int(averageProfit).formattedWithCommas) / session")
                    Divider().background(Color.white.opacity(0.1))
                    performanceLine(icon: "star.fill", color: .yellow, title: "Best Session", value: "$\(Int(bestSession?.profit ?? 0).formattedWithCommas)")
                    Divider().background(Color.white.opacity(0.1))
                    performanceLine(icon: "list.star", color: .orange, title: "Sessions", value: "\(totalSessions)")
                    Divider().background(Color.white.opacity(0.1))
                    performanceLine(icon: "clock.fill", color: .purple, title: "Hours", value: "\(Int(totalHoursPlayed))")
                    Divider().background(Color.white.opacity(0.1))
                    performanceLine(icon: "timer", color: .pink, title: "Avg. Session Length", value: String(format: "%.1f hrs", averageSessionLength))
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .padding(.bottom, 24) // Slightly reduced bottom padding
        }
        .background(AppBackgroundView().ignoresSafeArea())
    }

    // MARK: - Adaptive Stat Card
    @ViewBuilder
    private func adaptiveStatCard<Content: View>(
        title: String,
        icon: String,
        // height: CGFloat, // Removed fixed height
        accentColor: Color, // Added accent color
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) { // Reduced spacing
            HStack(spacing: 6) { // Reduced spacing
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium)) // Adjusted size
                    .foregroundColor(accentColor) // Use accent color
                    .frame(width: 14, alignment: .center) // Adjusted size
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded)) // Adjusted size
                    .foregroundColor(.white.opacity(0.75)) // Brighter
                Spacer()
            }
            
            Spacer(minLength: 4) // Reduced minLength
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 4) // Reduced minLength
        }
        .padding(10) // Slightly less padding for more transparency
        .frame(maxWidth: .infinity) // Allow horizontal expansion
        .fixedSize(horizontal: false, vertical: true) // Allow vertical adaptation
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.1) // More transparent glass
                  
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.02)) // Softer overlay
                
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                accentColor.opacity(0.3), // Use accent color in border
                                Color.white.opacity(0.04),
                                Color.clear
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75 // Thinner border
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Carousel Support Types
    private struct CarouselHighlight: Identifiable {
        let id = UUID()
        let type: HighlightType
        var title: String
        var iconName: String
        var primaryText: String
        var secondaryText: String?
        var tertiaryText: String?
    }

    private enum HighlightType {
        case multiplier, persona, location
    }

    // MARK: - Premium Highlights Carousel
    @ViewBuilder
    private func PremiumHighlightsCarousel(
        highestCashoutToBuyInRatio: (ratio: Double, session: Session)?,
        pokerPersona: (category: TimeOfDayCategory, dominantHours: String),
        topLocation: (location: String, count: Int)?
    ) -> some View {
        
        let highlights: [CarouselHighlight] = {
            var items: [CarouselHighlight] = []

            // Top Location (Hot Spot) - FIRST
            if let locData = topLocation {
                items.append(CarouselHighlight(
                    type: .location,
                    title: "Hot Spot",
                    iconName: "mappin.and.ellipse",
                    primaryText: locData.location,
                    secondaryText: "Played \(locData.count) times",
                    tertiaryText: nil
                ))
            }

            // Best Multiplier
            if let ratioData = highestCashoutToBuyInRatio {
                items.append(CarouselHighlight(
                    type: .multiplier,
                    title: "Best Multiplier",
                    iconName: "flame.fill", // Using system flame
                    primaryText: String(format: "%.1fx", ratioData.ratio),
                    secondaryText: "Buy-in: $\(Int(ratioData.session.buyIn).formattedWithCommas)",
                    tertiaryText: "Cash-out: $\(Int(ratioData.session.cashout).formattedWithCommas)"
                ))
            }

            // Poker Persona
            items.append(CarouselHighlight(
                type: .persona,
                title: "Your Style",
                iconName: pokerPersona.category.icon,
                primaryText: pokerPersona.category.rawValue,
                secondaryText: pokerPersona.dominantHours,
                tertiaryText: nil
            ))

            return items.filter { !$0.primaryText.isEmpty || $0.type == .persona } // Ensure persona always shows if available
        }()

        @State var selectedIndex = 0

        if highlights.isEmpty {
            VStack {
                Text("More insights available as you log sessions")
                    .font(.system(size: 14, weight: .medium, design: .rounded)) // Adjusted size
                    .foregroundColor(.gray.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill available space
            .background(
                RoundedRectangle(cornerRadius: 24) // Softer radius
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.1) // More subtle
            )
        } else {
            VStack(spacing: 8) {
                // TabView content - this should match win rate card height exactly
                TabView(selection: $selectedIndex) {
                    ForEach(highlights.indices, id: \.self) { index in
                        let highlight = highlights[index]
                        
                        VStack(alignment: .leading, spacing: 12) { // Adjusted spacing
                            // Header
                            HStack(spacing: 10) { // Adjusted spacing
                                Image(systemName: highlight.iconName)
                                    .font(.system(size: 20, weight: .semibold)) // Adjusted size
                                    .foregroundColor(highlight.type == .multiplier ? .orange : (highlight.type == .persona ? .cyan : .pink)) // Example colors
                                    .frame(width: 28, height: 28) // Adjusted size
                                
                                Text(highlight.title)
                                    .font(.system(size: 15, weight: .bold, design: .rounded)) // Adjusted size
                                    .foregroundColor(.white.opacity(0.9))
                            
                            Spacer()
                            }
                            
                            // Primary content
                            Text(highlight.primaryText)
                                .font(.system(size: highlight.type == .multiplier ? 38 : 26, weight: .bold, design: .rounded)) // Adjusted sizes
                                .foregroundColor(.white)
                                .lineLimit(1) // Ensure it fits
                                .minimumScaleFactor(0.7)
                            
                            // Secondary content
                            if let secondaryText = highlight.secondaryText {
                                Text(secondaryText)
                                    .font(.system(size: 14, weight: .medium, design: .rounded)) // Adjusted size
                                    .foregroundColor(.white.opacity(0.75))
                            }
                            
                            // Tertiary content
                            if let tertiaryText = highlight.tertiaryText {
                                Text(tertiaryText)
                                    .font(.system(size: 13, weight: .regular, design: .rounded)) // Adjusted size
                                    .foregroundColor(.white.opacity(0.65))
                            }
                            
                            Spacer(minLength: 0) // Ensure content pushes up
                        }
                        .padding(20) // Adjusted padding
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 24) // Softer radius
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.08) 
                                
                                RoundedRectangle(cornerRadius: 24)
                                    .fill(Color.white.opacity(0.02))
                                
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.15),
                                                Color.white.opacity(0.05),
                                                Color.clear
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.7 // Thinner
                                    )
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity) // Fill the exact frame given to carousel
                
                // Enhanced page indicator
                if highlights.count > 1 {
                    HStack(spacing: 7) { // Adjusted spacing
                        ForEach(highlights.indices, id: \.self) { index in
                            Capsule()
                                .fill(selectedIndex == index ? Color.white.opacity(0.85) : Color.white.opacity(0.3))
                                .frame(width: selectedIndex == index ? 20 : 7, height: 7) // Adjusted sizes
                                .animation(.spring(response: 0.35, dampingFraction: 0.65), value: selectedIndex)
                        }
                    }
                }
            }
        }
    }

    // New ViewBuilder function for a single stat card with glassy effect
    @ViewBuilder
    private func analyticsStatCard<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        statDetailColor: Color, // Color for icon and subtle accents
        height: CGFloat = 100, // Default height, can be overridden
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium)) // Slightly smaller icon
                    .foregroundColor(statDetailColor.opacity(0.85))
                    .frame(width: 18, alignment: .center) // Slightly smaller frame
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded)) // Slightly smaller title
                    .foregroundColor(Color.white.opacity(0.75))
                Spacer()
            }
            
            content() // This will contain the main stat value/display
                .frame(maxWidth: .infinity, alignment: .leading) 
                .padding(.top, 5) // Increased padding a bit for content separation

        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: height) 
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20) // Slightly larger radius
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.35) // Increased transparency (material is more see-through)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.05)) // Very subtle darker overlay for content pop

                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                statDetailColor.opacity(0.45), // Adjusted opacity for stroke
                                statDetailColor.opacity(0.15), 
                                Color.white.opacity(0.05) // More subtle white highlight
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1 // Thinner stroke
                    )
                
                // Optional: Softer Inner Glow instead of shadow for a smoother look
                RoundedRectangle(cornerRadius: 20)
                    .fill(statDetailColor)
                    .blur(radius: 25) // Large blur for a glow effect
                    .opacity(0.1) // Very subtle glow
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4) // Adjusted shadow
    }
    
    private func getTimeRangeLabel(for index: Int) -> String {
        // Ensure this uses the correct `timeRanges` array if it's defined at ProfileView level
        // The `timeRanges` array used for buttons should be ["24H", "1W", "1M", "6M", "1Y", "All"]
        // This function needs to align with that.
        guard index >= 0 && index < self.timeRanges.count else { return "Selected Period" }
        let range = self.timeRanges[index]
        switch range {
            case "24H": return "Past 24H"
            case "1W": return "Past week"
            case "1M": return "Past month"
            case "6M": return "Past 6 months"
            case "1Y": return "Past year"
            case "All": return "All time"
            default: return "Selected period"
        }
    }

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
    
    // Chart interaction helper functions
    private func handleChartTouch(at location: CGPoint, in geometry: GeometryProxy) {
        let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange).sorted(by: { $0.startDate < $1.startDate })
        
        guard !filteredSessions.isEmpty else { return }
        
        // Get ALL sessions sorted by date to calculate true cumulative bankroll
        let allSessionsSorted = sessionStore.sessions.sorted(by: { $0.startDate < $1.startDate })
        
        // Calculate cumulative data for filtered sessions but with true bankroll totals
        var cumulativeData: [(date: Date, profit: Double)] = []
        
        for session in filteredSessions {
            // Find this session's position in all sessions to calculate true cumulative
            let sessionsUpToThisPoint = allSessionsSorted.filter { $0.startDate <= session.startDate }
            let trueAccumulated = sessionsUpToThisPoint.reduce(0) { $0 + $1.profit }
            cumulativeData.append((date: session.startDate, profit: trueAccumulated))
        }
        
        // Find the closest data point to touch location
        let touchX = location.x
        let stepX = cumulativeData.count > 1 ? geometry.size.width / CGFloat(cumulativeData.count - 1) : geometry.size.width
        
        // Calculate which data point index is closest
        let index = Int(round(touchX / stepX))
        let clampedIndex = max(0, min(index, cumulativeData.count - 1))
        
        let dataPoint = cumulativeData[clampedIndex]
        let actualX = CGFloat(clampedIndex) * stepX
        
        // Calculate Y position using the SAME logic as the chart line
        let cumulativeProfits = cumulativeData.map { $0.profit }
        let minProfit = cumulativeProfits.min() ?? 0
        let maxProfit = max(cumulativeProfits.max() ?? 1, 1)
        let range = max(maxProfit - minProfit, 1)
        
        // Use exact same Y calculation as the chart path
        let normalized = range == 0 ? 0.5 : (dataPoint.profit - minProfit) / range
        let actualY = geometry.size.height * (1 - CGFloat(normalized))
        
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            selectedDataPoint = dataPoint
            touchLocation = CGPoint(x: actualX, y: actualY)
            showTooltip = true
        }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func formatTooltipDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        switch selectedTimeRange {
        case 0: // 24H
            formatter.dateFormat = "MMM d, HH:mm"
        case 1: // 1W
            formatter.dateFormat = "MMM d"
        case 2: // 1M
            formatter.dateFormat = "MMM d"
        case 3, 4: // 6M, 1Y
            formatter.dateFormat = "MMM d, yyyy"
        default: // All
            formatter.dateFormat = "MMM d, yyyy"
        }
        
        return formatter.string(from: date)
    }

    // MARK: - Existing helpers/components

    // MARK: - Highlight Card
    @ViewBuilder
    private func highlightCard(title: String, icon: String, primary: String, secondary: String, tertiary: String, accent: Color, width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            Text(primary)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            if !tertiary.isEmpty {
                Text(tertiary)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
        }
        .padding(16)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Material.ultraThinMaterial)
                .opacity(0.08)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Performance Line
    @ViewBuilder
    private func performanceLine(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Win Rate Card (square)
    private struct WinRateCard: View {
        let winRate: Double

        var body: some View {
            let squareSize: CGFloat = (UIScreen.main.bounds.width - 50) / 3
            let dynamicRadius: CGFloat = squareSize * 0.15
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.cyan)
                        .frame(width: 14)
                    Text("Win Rate")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                }

                GeometryReader { proxy in
                    let availableSize = min(proxy.size.width, proxy.size.height)
                    let wheelSize = availableSize * 0.95 // Reduced from 1 to 0.95 for slightly smaller wheel
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 8)
                            .frame(width: wheelSize, height: wheelSize)
                        Circle()
                            .trim(from: 0, to: CGFloat(winRate) / 100)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.cyan, Color.cyan.opacity(0.6)]),
                                    startPoint: .top, endPoint: .bottom),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: wheelSize, height: wheelSize)
                        Text("\(Int(winRate))%")
                            .font(.system(size: min(wheelSize * 0.25, 28), weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

            }
            .padding(10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: dynamicRadius)
                        .fill(Material.ultraThinMaterial)
                        .opacity(0.1)
                    RoundedRectangle(cornerRadius: dynamicRadius)
                        .fill(Color.white.opacity(0.02))
                    RoundedRectangle(cornerRadius: dynamicRadius)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.cyan.opacity(0.3), Color.white.opacity(0.04), Color.clear]),
                                startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 0.75)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: dynamicRadius))
        }
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

// MARK: - Profile Card View (Modified from ProfileContent)
struct ProfileCardView: View {
    let userId: String
    @EnvironmentObject private var userService: UserService
    @Binding var showEdit: Bool
    @Binding var showingFollowersSheet: Bool
    @Binding var showingFollowingSheet: Bool

    var body: some View {
        VStack(spacing: 15) {
                if let profile = userService.currentUserProfile {
                    VStack(alignment: .leading, spacing: 15) {
                        // Top Section: Avatar, Name, Username, Location, Stats
                        HStack(spacing: 16) {
                        // Profile picture
                            if let url = profile.avatarURL, let imageURL = URL(string: url) {
                                AsyncImage(url: imageURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                } else {
                                    PlaceholderAvatarView(size: 60)
                                }
                            }
                        } else {
                            PlaceholderAvatarView(size: 60)
                        }
                            
                            // Middle: Name, Username, Location
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName ?? "@\(profile.username)")
                                .font(.system(size: 20, weight: .bold))
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
                                Button(action: { showingFollowersSheet = true }) {
                                    HStack(spacing: 2) {
                                        Text("\(profile.followersCount)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("followers")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            
                                Button(action: { showingFollowingSheet = true }) {
                                    HStack(spacing: 2) {
                                        Text("\(profile.followingCount)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("following")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
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
            }
        }
        .onAppear {
            if userService.currentUserProfile == nil {
                Task { try? await userService.fetchUserProfile() }
            }
        }
    }
}

// MARK: - Activity Content View (Recent Posts)
struct ActivityContentView: View {
    let userId: String 
    @EnvironmentObject private var userService: UserService 
    @EnvironmentObject private var postService: PostService
    @Binding var selectedPostForNavigation: Post? 
    // @Binding var showingPostDetailSheet: Bool // This binding is no longer needed here

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if postService.isLoading && postService.posts.filter({ $0.userId == userId }).isEmpty {
                 ProgressView().padding().frame(maxWidth: .infinity, alignment: .center)
            } else if postService.posts.filter({ $0.userId == userId }).isEmpty {
                Text("No recent posts to display.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .background(Color.black.opacity(0.15).cornerRadius(12))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(postService.posts.filter { $0.userId == userId }) { post in 
                            PostView(
                                post: post,
                                onLike: { Task { try? await postService.toggleLike(postId: post.id ?? "", userId: userService.currentUserProfile?.id ?? "") } },
                                onComment: { /* If PostView has a comment button that navigates, it might need its own programmatic trigger */ },
                                userId: userService.currentUserProfile?.id ?? ""
                            )
                            .padding(.leading, 8) // Reduced horizontal padding, more to the left
                            .contentShape(Rectangle()) // Ensure the whole area is tappable
                            .onTapGesture {
                                // Direct navigation instead of sheet
                                self.selectedPostForNavigation = post
                            }
                            .background(
                                NavigationLink(
                                    destination: PostDetailView(post: post, userId: userId),
                                    isActive: Binding<Bool>(
                                       get: { selectedPostForNavigation?.id == post.id },
                                       set: { if !$0 { selectedPostForNavigation = nil } }
                                    ),
                                    label: { EmptyView() }
                                ).opacity(0)
                            )
                        }
                    }
                    .padding(.top, 0) // Removed vertical padding, posts will be closer to the top
                }
                .padding(.top, 8) // Reduced top padding for the ScrollView
                .padding(.top, 10) // Reduced from 50 to 10 points to minimize space under header
            }
        }
        .padding(.bottom, 8) // Reduced bottom padding for the entire ActivityContentView
        // .onAppear is handled by ProfileView's .onChange for selectedTab
    }
}

// MARK: - Existing helpers/components
// Keep NavigationButton, StatItem, SettingsView, SettingsGroup, SettingsRow (unchanged)

// MARK: - SettingsView
struct SettingsView: View {
    let userId: String
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var sessionStore: SessionStore // Add SessionStore
    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var deleteError: String? = nil
    @State private var isDeleting = false
    @State private var pushNotificationsEnabled: Bool = true // Added for push notification toggle
    @State private var showCSVImporter: Bool = false // For Pokerbase import
    @State private var importStatusMessage: String? = nil // Shows success/failure
    @State private var showEmergencyResetConfirmation = false // Add confirmation state
    @State private var showPAImporter: Bool = false // Poker Analytics
    @State private var paStatusMessage: String? = nil
    @State private var showPBTImporter: Bool = false // Poker Bankroll Tracker
    @State private var pbtStatusMessage: String? = nil
    
    // Add enum and state for consolidated file import
    enum ImportType {
        case pokerbase, pokerAnalytics, pbt
    }
    @State private var currentImportType: ImportType = .pokerbase
    @State private var showFileImporter: Bool = false
    
    var body: some View {
        ZStack {
            // Use AppBackgroundView as the background
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                Text("Settings")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                
                // Push Notifications Toggle
                HStack {
                    Text("Push Notifications")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Toggle("", isOn: $pushNotificationsEnabled)
                        .labelsHidden()
                        .tint(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))) // Green accent
                        .onChange(of: pushNotificationsEnabled) { newValue in
                            // TODO: Implement logic to update user's push notification preferences
                            print("Push notifications toggled to: \(newValue)")
                            // Example: APIManager.shared.updatePushNotificationSetting(enabled: newValue)
                        }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                )
                .padding(.horizontal, 20)
                
                // Emergency Session Reset Button
                Button(action: { showEmergencyResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text("Reset Session Data")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                        Spacer()
                        Text("Emergency")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                
                // Import from Pokerbase Button
                Button(action: { 
                    print("Pokerbase import button tapped")
                    currentImportType = .pokerbase
                    showFileImporter = true
                    print("showFileImporter set to: \(showFileImporter) for type: \(currentImportType)")
                }) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        Text("Import from Pokerbase")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        Spacer()
                        Text("CSV")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                
                // Import from Poker Analytics 6 Button
                Button(action: { 
                    print("Poker Analytics import button tapped")
                    currentImportType = .pokerAnalytics
                    showFileImporter = true
                    print("showFileImporter set to: \(showFileImporter) for type: \(currentImportType)")
                }) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundColor(.cyan)
                        Text("Import from Poker Analytics")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.cyan)
                        Spacer()
                        Text("TSV/CSV")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                
                // Import from Poker Bankroll Tracker Button
                Button(action: { 
                    print("PBT import button tapped")
                    currentImportType = .pbt
                    showFileImporter = true
                    print("showFileImporter set to: \(showFileImporter) for type: \(currentImportType)")
                }) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundColor(.purple)
                        Text("Import from Poker Bankroll Tracker")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.purple)
                        Spacer()
                        Text("CSV")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    )
                }
                .padding(.horizontal, 20)
                
                Spacer()
                
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
                
                // Delete Account Button
                Button(action: { showDeleteConfirmation = true }) {
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

                // Company Info
                VStack(spacing: 8) {
                    Text("stackpoker.gg")
                        .font(.plusJakarta(.footnote)) // Using Plus Jakarta Sans font
                        .foregroundColor(.gray)
                        .onTapGesture {
                            if let url = URL(string: "https://stackpoker.gg") {
                                UIApplication.shared.open(url)
                            }
                        }

                    Text("support@stackpoker.gg")
                        .font(.plusJakarta(.footnote)) // Using Plus Jakarta Sans font
                        .foregroundColor(.gray)
                        .onTapGesture {
                            if let url = URL(string: "mailto:support@stackpoker.gg") {
                                UIApplication.shared.open(url)
                            }
                        }
                }
                .padding(.top, 30) // Space above company info
                .padding(.bottom, 120) // Maintained bottom padding for tab bar space
            }
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
        .alert("Reset Session Data?", isPresented: $showEmergencyResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                sessionStore.emergencySessionReset()
            }
        } message: {
            Text("This will clear all session data if you're experiencing issues with stuck sessions. Use this only if sessions appear active when they shouldn't be.")
        }
        .alert("Import Result", isPresented: Binding(get: { importStatusMessage != nil }, set: { if !$0 { importStatusMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importStatusMessage ?? "")
        }
        .alert("Poker Analytics Import", isPresented: Binding(get: { paStatusMessage != nil }, set: { if !$0 { paStatusMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(paStatusMessage ?? "")
        }
        .alert("PBT Import Result", isPresented: Binding(get: { pbtStatusMessage != nil }, set: { if !$0 { pbtStatusMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pbtStatusMessage ?? "")
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .text, .data]) { result in
            print("Consolidated file importer triggered for type: \(currentImportType)")
            switch result {
            case .success(let url):
                print("File selected: \(url)")
                switch currentImportType {
                case .pokerbase:
                    sessionStore.importSessionsFromPokerbaseCSV(fileURL: url) { importResult in
                        switch importResult {
                        case .success(let count):
                            importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Pokerbase."
                        case .failure(let error):
                            importStatusMessage = "Pokerbase import failed: \(error.localizedDescription)"
                        }
                    }
                case .pokerAnalytics:
                    sessionStore.importSessionsFromPokerAnalyticsCSV(fileURL: url) { res in
                        switch res {
                        case .success(let count):
                            paStatusMessage = "Imported \(count) session" + (count == 1 ? "" : "s") + " from Poker Analytics."
                        case .failure(let err):
                            paStatusMessage = "Poker Analytics import failed: \(err.localizedDescription)"
                        }
                    }
                case .pbt:
                    sessionStore.importSessionsFromPBTCSV(fileURL: url) { res in
                        switch res {
                        case .success(let count):
                            pbtStatusMessage = "Imported \(count) session" + (count == 1 ? "" : "s") + " from PBT."
                        case .failure(let err):
                            pbtStatusMessage = "PBT import failed: \(err.localizedDescription)"
                        }
                    }
                }
            case .failure(let error):
                print("File picker error: \(error)")
                switch currentImportType {
                case .pokerbase:
                    importStatusMessage = "Failed to pick Pokerbase file: \(error.localizedDescription)"
                case .pokerAnalytics:
                    paStatusMessage = "Failed to pick Poker Analytics file: \(error.localizedDescription)"
                case .pbt:
                    pbtStatusMessage = "Failed to pick PBT file: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func signOut() {
        // Use the AuthViewModel's signOut method for proper cleanup
        authViewModel.signOut()
        
        // No need to manually set authState as the listener will handle it
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

                }
                
                await MainActor.run {
                    isDeleting = false
                    // The app will automatically redirect to the sign-in page due to auth state change
                    authViewModel.checkAuthState()
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
        
        // Delete user's follow relationships from userFollows collection
        // Delete where user is a follower (following someone)
        let followingDocs = try await db.collection("userFollows")
            .whereField("followerId", isEqualTo: userId)
            .getDocuments()
        
        for doc in followingDocs.documents {
            batch.deleteDocument(doc.reference)
        }
        
        // Delete where user is being followed (someone following them)
        let followerDocs = try await db.collection("userFollows")
            .whereField("followeeId", isEqualTo: userId)
            .getDocuments()
        
        for doc in followerDocs.documents {
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

        }
    }
}

// MARK: - Settings Components
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

// Add at the bottom of the file, outside any struct
extension Int {
    var formattedWithCommas: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

// Helper struct for clarity, though often not strictly necessary for just transparency.
// struct ClearBackground: View { // This helper is no longer used with the new structure
//     var body: some View {
//         Color.clear
//     }
// }




