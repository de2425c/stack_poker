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
    @StateObject private var sessionStore: SessionStore
    @StateObject private var handStore: HandStore
    @StateObject private var bankrollStore: BankrollStore
    @StateObject private var challengeService: ChallengeService
    @StateObject private var challengeProgressTracker: ChallengeProgressTracker
    @EnvironmentObject private var postService: PostService
    @State private var showEdit = false
    @State private var showSettings = false
    @State private var selectedPostForNavigation: Post? = nil
    @State private var showingBankrollSheet = false
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
    @State private var selectedGraphTab = 0 // 0 = Bankroll, 1 = Profit, 2 = Monthly
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"] // Used by analyticsDetailContent
    
    // Performance stats customization
    @State private var isCustomizingStats = false
    @State private var selectedStats: [PerformanceStat] = [
        .avgProfit, .bestSession, .winRate, .sessions, .hours, .avgSessionLength
    ]
    @State private var isDraggingAny = false
    
    // Chart interaction states
    @State private var selectedDataPoint: (date: Date, profit: Double)? = nil
    @State private var touchLocation: CGPoint = .zero
    @State private var showTooltip: Bool = false
    
    // MARK: - Analytics filtering
    @State private var showFilterSheet = false
    @State private var analyticsFilter = AnalyticsFilter()
    
    // Convenience: sessions that satisfy current filter (ignores time-range)
    private var filteredSessions: [Session] {
        sessionStore.sessions.filter { sessionMatchesFilter($0) }
    }
    
    init(userId: String) {
        self.userId = userId
        let bankrollStore = BankrollStore(userId: userId)
        let sessionStore = SessionStore(userId: userId, bankrollStore: bankrollStore)
        let handStore = HandStore(userId: userId)
        let challengeService = ChallengeService(userId: userId, bankrollStore: bankrollStore)
        
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _handStore = StateObject(wrappedValue: handStore)
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
                        }

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
                            Text("View and manage your stakes")
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
                                Text("Set goals and track your poker journey")
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
            .scrollDisabled(isDraggingAny)
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
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { showFilterSheet = true }) {
                                Image(systemName: analyticsFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .overlay(EmptyView())
            }
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .background(AppBackgroundView().ignoresSafeArea(.all))
            .accentColor(.white)
            .environmentObject(sessionStore)
            .environmentObject(userService)
            // Filter configuration sheet
            .sheet(isPresented: $showFilterSheet) {
                let uniqueGames = Array(Set(sessionStore.sessions.map { $0.gameName.trimmingCharacters(in: .whitespaces) })).filter { !$0.isEmpty }.sorted()
                AnalyticsFilterSheet(filter: $analyticsFilter, availableGames: uniqueGames)
            }
            // Bankroll adjustment sheet
            .sheet(isPresented: $showingBankrollSheet) {
                BankrollAdjustmentSheet(bankrollStore: bankrollStore, currentTotalBankroll: totalBankroll)
            }
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
            .environmentObject(StakeService())
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
    
    // MARK: - Analytics Helper Properties (Unchanged, used by analyticsDetailContent)
    private var totalBankroll: Double {
        let sessionProfit = filteredSessions.reduce(0) { $0 + $1.profit }
        return sessionProfit + bankrollStore.bankrollSummary.currentTotal
    }
    
    private var selectedTimeRangeProfit: Double {
        let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
        return filteredSessions.reduce(0) { $0 + $1.profit }
    }
    
    private func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        // First, apply user-defined analytics filters
        let preFiltered = filteredSessions
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return preFiltered.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return preFiltered.filter { $0.startDate >= oneYearAgo }
        default: // All
            return preFiltered
        }
    }
    
    private var winRate: Double {
        let totalSessions = filteredSessions.count
        if totalSessions == 0 { return 0 }
        let winningSessions = filteredSessions.filter { $0.profit > 0 }.count
        return Double(winningSessions) / Double(totalSessions) * 100
    }
    
    private var averageProfit: Double {
        let totalSessions = filteredSessions.count
        if totalSessions == 0 { return 0 }
        return totalBankroll / Double(totalSessions)
    }
    
    private var totalSessions: Int {
        filteredSessions.count
    }
    
    private var bestSession: (profit: Double, id: String)? {
        if let best = filteredSessions.max(by: { $0.profit < $1.profit }) {
            return (best.profit, best.id)
        }
        return nil
    }
    
    // MARK: - New Analytics Helper Properties
    private var totalHoursPlayed: Double {
        filteredSessions.reduce(0) { $0 + $1.hoursPlayed }
    }

    private var averageSessionLength: Double {
        if totalSessions == 0 { return 0 }
        return totalHoursPlayed / Double(totalSessions)
    }
    
    private var dollarPerHour: Double {
        if totalHoursPlayed == 0 { return 0 }
        return totalBankroll / totalHoursPlayed
    }
    
    private var bbPerHour: Double {
        if totalHoursPlayed == 0 { return 0 }
        // Calculate average big blind from sessions
        let totalBBs = filteredSessions.compactMap { session -> Double? in
            let digits = session.stakes.replacingOccurrences(of: " $", with: "")
            let comps = digits.replacingOccurrences(of: "$", with: "").split(separator: "/")
            guard comps.count == 2, let bb = Double(comps[1]) else { return nil }
            return bb
        }
        
        if totalBBs.isEmpty { return 0 }
        let avgBB = totalBBs.reduce(0, +) / Double(totalBBs.count)
        if avgBB == 0 { return 0 }
        return dollarPerHour / avgBB
    }
    
    private func getStatValue(for stat: PerformanceStat) -> String {
        switch stat {
        case .avgProfit:
            return "$\(Int(averageProfit).formattedWithCommas) / session"
        case .bestSession:
            return "$\(Int(bestSession?.profit ?? 0).formattedWithCommas)"
        case .winRate:
            return "\(Int(winRate))%"
        case .sessions:
            return "\(totalSessions)"
        case .hours:
            return "\(Int(totalHoursPlayed))"
        case .avgSessionLength:
            return String(format: "%.1f hrs", averageSessionLength)
        case .dollarPerHour:
            return "$\(Int(dollarPerHour).formattedWithCommas)/hr"
        case .bbPerHour:
            return String(format: "%.1f BB/hr", bbPerHour)
        }
    }

    private var highestCashoutToBuyInRatio: (ratio: Double, session: Session)? {
        guard !filteredSessions.isEmpty else { return nil }
        
        var maxRatio: Double = 0
        var sessionWithMaxRatio: Session? = nil
        
        for session in filteredSessions {
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
        guard !filteredSessions.isEmpty else {
            return (.unknown, "N/A")
        }

        var morningSessions = 0 // 5 AM - 11:59 AM
        var afternoonSessions = 0 // 12 PM - 4:59 PM
        var eveningSessions = 0   // 5 PM - 8:59 PM
        var nightSessions = 0     // 9 PM - 4:59 AM

        let calendar = Calendar.current
        for session in filteredSessions {
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
        guard !filteredSessions.isEmpty else { return nil }

        let locationStrings = filteredSessions.map { displayLocation(for: $0) }
        let locationCounts = locationStrings.reduce(into: [String: Int]()) { counts, loc in
            counts[loc, default: 0] += 1
        }
        guard let (loc, cnt) = locationCounts.max(by: { $0.value < $1.value }) else { return nil }
        return (loc, cnt)
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
                    // Dynamic header title based on selected graph tab
                    Text(selectedGraphTab == 0 ? "Bankroll" : (selectedGraphTab == 1 ? "Profit" : "Monthly Profit"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    // Show selected data point profit or aggregated value with edit button for bankroll
                    HStack(alignment: .bottom, spacing: 12) {
                        Text(selectedDataPoint != nil ?
                             "$\(Int(selectedDataPoint!.profit).formattedWithCommas)" :
                             (selectedGraphTab == 0 ? "$\(Int(totalBankroll).formattedWithCommas)" : 
                              (selectedGraphTab == 1 ? "$\(Int(filteredSessions.reduce(0){$0+$1.profit}).formattedWithCommas)" : 
                               "$\(Int(monthlyProfitCurrent()).formattedWithCommas)")))
                            .font(.system(size: selectedDataPoint != nil ? 40 : 36, weight: .bold))
                            .foregroundColor(.white)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedDataPoint?.profit)
                        
                        // Edit button only for bankroll view
                        if selectedGraphTab == 0 {
                            Button(action: { showingBankrollSheet = true }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Edit")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Material.ultraThinMaterial)
                                            .opacity(0.2)
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.white.opacity(0.02))
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                    }
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
        
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
                    if filteredSessions.isEmpty {
                        Text("No sessions recorded")
                            .foregroundColor(.gray)
                            .frame(height: 220)
                            .frame(maxWidth: .infinity) // Ensure it centers if no data
                    } else {
                        // Swipeable Graph Carousel
                        SwipeableGraphCarousel(
                            sessions: filteredSessions,
                            bankrollTransactions: bankrollStore.transactions,
                            selectedTimeRange: $selectedTimeRange,
                            timeRanges: timeRanges,
                            selectedGraphIndex: $selectedGraphTab,
                            onChartTouch: { location, geometry in
                                // Handle touch for tooltip
                                if selectedGraphTab < 2 {
                                    let touchX = location.x
                                    let normalizedX = touchX / geometry.size.width
                                    
                                    if !filteredSessions.isEmpty {
                                        let index = Int(normalizedX * CGFloat(filteredSessions.count - 1))
                                        let clampedIndex = max(0, min(index, filteredSessions.count - 1))
                                        let session = filteredSessions.sorted { $0.startDate < $1.startDate }[clampedIndex]
                                        
                                        var cumulativeProfit = 0.0
                                        for i in 0...clampedIndex {
                                            cumulativeProfit += filteredSessions.sorted { $0.startDate < $1.startDate }[i].profit
                                        }
                                        
                                        selectedDataPoint = (date: session.startDate, profit: cumulativeProfit)
                                        touchLocation = location
                                        showTooltip = true
                                    }
                                }
                            },
                            onTouchEnd: {
                                showTooltip = false
                                selectedDataPoint = nil
                            },
                            showTooltip: showTooltip,
                            touchLocation: touchLocation,
                            selectedDataPoint: selectedDataPoint
                        )
                        .frame(height: 280)
                    }
                }
                // Graph now full width
                
                // Spacer for consistent layout
                Spacer()
                    .frame(height: 16)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
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

                // Performance Stats with Customization
                HStack {
                    Text("PERFORMANCE STATS")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.gray.opacity(0.8))
                    
                    if !isCustomizingStats {
                        Text("\(selectedStats.count)/\(PerformanceStat.allCases.count)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            isCustomizingStats.toggle()
                        }
                    }) {
                        Text(isCustomizingStats ? "Done" : "Customize Stats")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                
                if isCustomizingStats {
                    // Customization Interface
                    CustomizeStatsView(selectedStats: $selectedStats, isDraggingAny: $isDraggingAny)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    // Regular Stats Display as Beautiful Boxes
                    if selectedStats.isEmpty {
                        Text("No stats selected. Tap 'Customize Stats' to add some.")
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 20)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 16) {
                            ForEach(selectedStats, id: \.id) { stat in
                                StatDisplayCard(
                                    stat: stat,
                                    value: getStatValue(for: stat)
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
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
        
        // Get ALL sessions that respect the active filter, sorted by date
        let allSessionsSorted = filteredSessions.sorted(by: { $0.startDate < $1.startDate })
        
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

    // MARK: - Session Filter Logic
    private func sessionMatchesFilter(_ session: Session) -> Bool {
        // Game type
        if analyticsFilter.gameType == .cash && !session.gameType.lowercased().contains("cash") {
            return false
        }
        if analyticsFilter.gameType == .tournament && !session.gameType.lowercased().contains("tournament") {
            return false
        }

        // Stake level
        let level = stakeLevel(for: session)
        if analyticsFilter.stakeLevel != .all && analyticsFilter.stakeLevel != level {
            return false
        }

        // Location
        if let desired = analyticsFilter.location {
            if session.gameName.trimmingCharacters(in: .whitespaces) != desired { return false }
        }

        // Session length
        switch analyticsFilter.sessionLength {
        case .under2:
            if session.hoursPlayed >= 2 { return false }
        case .twoToFour:
            if session.hoursPlayed < 2 || session.hoursPlayed > 4 { return false }
        case .over4:
            if session.hoursPlayed <= 4 { return false }
        default:
            break
        }

        // Profitability
        switch analyticsFilter.profitability {
        case .winning:
            if session.profit <= 0 { return false }
        case .losing:
            if session.profit >= 0 { return false }
        default: break
        }

        // Time of day
        let hour = Calendar.current.component(.hour, from: session.startTime)
        switch analyticsFilter.timeOfDay {
        case .morning:
            if !(5..<12).contains(hour) { return false }
        case .afternoon:
            if !(12..<17).contains(hour) { return false }
        case .lateNight:
            if !((22...23).contains(hour) || (0..<6).contains(hour)) { return false }
        default: break
        }

        // Day of week (1 = Sunday)
        if analyticsFilter.dayOfWeek != .all {
            let weekdaySymbols: [DayOfWeekFilter] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            let weekdayIndex = Calendar.current.component(.weekday, from: session.startDate) - 1 // 0–6
            let sessionDay = weekdaySymbols[weekdayIndex]
            if sessionDay != analyticsFilter.dayOfWeek { return false }
        }

        return true
    }

    private func stakeLevel(for session: Session) -> StakeLevelFilter {
        // Attempt to parse big blind value from the stakes string (e.g., "$1/$2")
        let digits = session.stakes.replacingOccurrences(of: " $", with: "")
        let comps = digits.replacingOccurrences(of: "$", with: "").split(separator: "/")
        guard comps.count == 2, let bb = Double(comps[1]) else {
            return .all
        }
        switch bb {
        case ..<1: return .micro
        case ..<3: return .low
        case ..<10: return .mid
        default: return .high
        }
    }

    // Helper: unified display string for location / game & stakes
    private func displayLocation(for session: Session) -> String {
        if session.gameType.lowercased().contains("cash") {
            // e.g. "PokerStars $1/$2"
            return "\(session.gameName) \(session.stakes)".trimmingCharacters(in: .whitespaces)
        }
        // tournaments – use location if available otherwise series/gameName
        return (session.location ?? session.gameName).trimmingCharacters(in: .whitespaces)
    }

    private func monthlyProfitCurrent() -> Double {
        let calendar = Calendar.current
        let now = Date()
        let month = calendar.component(.month, from: now)
        let year = calendar.component(.year, from: now)
        
        let sessionProfit = filteredSessions.filter { session in
            calendar.component(.month, from: session.startDate) == month && calendar.component(.year, from: session.startDate) == year
        }.reduce(0) { $0 + $1.profit }
        
        let bankrollProfit = bankrollStore.transactions.filter { txn in
            calendar.component(.month, from: txn.timestamp) == month && calendar.component(.year, from: txn.timestamp) == year
        }.reduce(0) { $0 + $1.amount }
        
        return sessionProfit + bankrollProfit
    }

    // Capsule ticker view
    @ViewBuilder
    private func CapsuleTicker(amount: Double, label: String) -> some View {
        let isPositive = amount >= 0
        let color = isPositive ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : Color.red
        HStack(spacing: 4) {
            Image(systemName: isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 9))
            Text("$\(abs(Int(amount)).formattedWithCommas)")
                .font(.system(size: 12, weight: .medium))
            Text(label.uppercased())
                .font(.system(size: 11))
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
        )
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

// MARK: - Performance Stat Enum
enum PerformanceStat: String, CaseIterable, Identifiable, Equatable {
    case avgProfit = "avg_profit"
    case bestSession = "best_session"
    case winRate = "win_rate"
    case sessions = "sessions"
    case hours = "hours"
    case avgSessionLength = "avg_session_length"
    case dollarPerHour = "dollar_per_hour"
    case bbPerHour = "bb_per_hour"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .avgProfit: return "Avg. Profit"
        case .bestSession: return "Best Session"
        case .winRate: return "Win Rate"
        case .sessions: return "Sessions"
        case .hours: return "Hours"
        case .avgSessionLength: return "Avg. Session Length"
        case .dollarPerHour: return "$/Hour"
        case .bbPerHour: return "BB/Hour"
        }
    }
    
    var iconName: String {
        switch self {
        case .avgProfit: return "dollarsign.circle.fill"
        case .bestSession: return "star.fill"
        case .winRate: return "chart.pie.fill"
        case .sessions: return "list.star"
        case .hours: return "clock.fill"
        case .avgSessionLength: return "timer"
        case .dollarPerHour: return "chart.line.uptrend.xyaxis"
        case .bbPerHour: return "speedometer"
        }
    }
    
    var color: Color {
        switch self {
        case .avgProfit: return .green
        case .bestSession: return .yellow
        case .winRate: return .cyan
        case .sessions: return .orange
        case .hours: return .purple
        case .avgSessionLength: return .pink
        case .dollarPerHour: return .mint
        case .bbPerHour: return .teal
        }
    }
}

// MARK: - Customize Stats View
struct CustomizeStatsView: View {
    @Binding var selectedStats: [PerformanceStat]
    @Binding var isDraggingAny: Bool
    
    @State private var allowReordering = true
    @State private var combinedItems: [StatItem] = []
    
    private var availableStats: [PerformanceStat] {
        PerformanceStat.allCases.filter { !selectedStats.contains($0) }
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Selected Stats Section Header
            HStack {
                Text("Selected Stats")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("\(selectedStats.count)/\(PerformanceStat.allCases.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                
                Spacer()
            }
            
            // Combined Reorderable List with Visual Sections
            VStack(spacing: 8) {
                ReorderableForEach($combinedItems, allowReordering: $allowReordering) { item, isDragged in
                    Group {
                        if item.isHeader {
                            // Section header
                            HStack {
                                Text(item.headerTitle ?? "")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, item.headerTitle == "Available Stats" ? 16 : 0)
                        } else if let stat = item.stat {
                            // Stat card
                            ReorderableStatCard(
                                stat: stat,
                                isSelected: item.isSelected,
                                isDragged: isDragged,
                                onTap: {
                                    withAnimation(.spring()) {
                                        if item.isSelected {
                                            selectedStats.removeAll { $0 == stat }
                                        } else {
                                            selectedStats.append(stat)
                                        }
                                        updateCombinedItems()
                                    }
                                }
                            )
                        } else {
                            // Empty state
                            Text(item.emptyMessage ?? "")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                                )
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .onAppear {
            updateCombinedItems()
        }
        .onChange(of: selectedStats) { _ in
            isDraggingAny = false
        }
    }
    
    private func updateCombinedItems() {
        var newItems: [StatItem] = []
        
        // Selected Stats Section
        if selectedStats.isEmpty {
            newItems.append(StatItem(emptyMessage: "Drag stats here to display them"))
        } else {
            for stat in selectedStats {
                newItems.append(StatItem(stat: stat, isSelected: true))
            }
        }
        
        // Available Stats Section Header
        newItems.append(StatItem(headerTitle: "Available Stats"))
        
        // Available Stats
        if availableStats.isEmpty {
            newItems.append(StatItem(emptyMessage: "All stats are currently selected"))
        } else {
            for stat in availableStats {
                newItems.append(StatItem(stat: stat, isSelected: false))
            }
        }
        
        combinedItems = newItems
    }
}

// MARK: - StatItem for Combined List
struct StatItem: Identifiable, Hashable {
    let id = UUID()
    let stat: PerformanceStat?
    let isSelected: Bool
    let isHeader: Bool
    let headerTitle: String?
    let emptyMessage: String?
    
    init(stat: PerformanceStat, isSelected: Bool) {
        self.stat = stat
        self.isSelected = isSelected
        self.isHeader = false
        self.headerTitle = nil
        self.emptyMessage = nil
    }
    
    init(headerTitle: String) {
        self.stat = nil
        self.isSelected = false
        self.isHeader = true
        self.headerTitle = headerTitle
        self.emptyMessage = nil
    }
    
    init(emptyMessage: String) {
        self.stat = nil
        self.isSelected = false
        self.isHeader = false
        self.headerTitle = nil
        self.emptyMessage = emptyMessage
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: StatItem, rhs: StatItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Stat Display Card (Main View)
struct StatDisplayCard: View {
    let stat: PerformanceStat
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: stat.iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(stat.color)
                    .frame(width: 24)
                
                Text(stat.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(stat.color.opacity(0.2), lineWidth: 1)
                )
        )
        .frame(height: 100)
    }
}

// MARK: - Reorderable Stat Card Component
struct ReorderableStatCard: View {
    let stat: PerformanceStat
    let isSelected: Bool
    let isDragged: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag handle (only for selected stats)
            if isSelected {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.6))
                    .frame(width: 20)
            }
            
            // Icon
            Image(systemName: stat.iconName)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(stat.color)
                .frame(width: 20)
            
            // Title
            Text(stat.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Action button
            Button(action: onTap) {
                Image(systemName: isSelected ? "xmark" : "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? .red : .green)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill((isSelected ? Color.red : Color.green).opacity(0.15))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDragged ? Color.black.opacity(0.3) : Color.black.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            isDragged ? stat.color.opacity(0.5) : Color.gray.opacity(0.2), 
                            lineWidth: isDragged ? 2 : 1
                        )
                )
        )
        .scaleEffect(isDragged ? 1.05 : 1.0)
        .shadow(color: isDragged ? Color.black.opacity(0.3) : Color.clear, radius: isDragged ? 8 : 0, y: isDragged ? 4 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragged)
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
    // Consolidated import states
    @State private var showImportOptionsSheet = false
    @State private var currentImportType: ImportType = .pokerbase
    @State private var showFileImporter: Bool = false
    @State private var importStatusMessage: String? = nil
    @State private var isImporting = false
    
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
                
                // Consolidated Import CSV Button
                Button(action: { 
                    showImportOptionsSheet = true
                }) {
                    HStack {
                        Image(systemName: "tray.and.arrow.down")
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        Text("Import CSV")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        Spacer()
                        Text("Multiple Formats")
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
            
            // Simple loading overlay
            if isImporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                            .scaleEffect(1.2)
                        
                        Text("Importing \(currentImportType.title) data...")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 0.95)))
                            .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
                    )
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isImporting)
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
        .alert("Import Result", isPresented: Binding(get: { importStatusMessage != nil }, set: { if !$0 { importStatusMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importStatusMessage ?? "")
        }
        .sheet(isPresented: $showImportOptionsSheet) {
            ImportOptionsSheet(
                onImportSelected: { importType in
                    currentImportType = importType
                    showFileImporter = true
                }
            )
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .text, .data]) { result in
            print("Consolidated file importer triggered for type: \(currentImportType)")
            switch result {
            case .success(let url):
                print("File selected: \(url)")
                isImporting = true
                switch currentImportType {
                case .pokerbase:
                    sessionStore.importSessionsFromPokerbaseCSV(fileURL: url) { importResult in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch importResult {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Pokerbase."
                            case .failure(let error):
                                importStatusMessage = "Pokerbase import failed: \(error.localizedDescription)"
                            }
                        }
                    }
                case .pokerAnalytics:
                    sessionStore.importSessionsFromPokerAnalyticsCSV(fileURL: url) { res in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch res {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Poker Analytics."
                            case .failure(let err):
                                importStatusMessage = "Poker Analytics import failed: \(err.localizedDescription)"
                            }
                        }
                    }
                case .pbt:
                    sessionStore.importSessionsFromPBTCSV(fileURL: url) { res in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch res {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Poker Bankroll Tracker."
                            case .failure(let err):
                                importStatusMessage = "Poker Bankroll Tracker import failed: \(err.localizedDescription)"
                            }
                        }
                    }
                case .regroup:
                    sessionStore.importSessionsFromRegroupCSV(fileURL: url) { res in
                        DispatchQueue.main.async {
                            isImporting = false
                            switch res {
                            case .success(let count):
                                importStatusMessage = "Successfully imported \(count) session" + (count == 1 ? "" : "s") + " from Regroup."
                            case .failure(let err):
                                importStatusMessage = "Regroup import failed: \(err.localizedDescription)"
                            }
                        }
                    }
                }
            case .failure(let error):
                print("File picker error: \(error)")
                importStatusMessage = "Failed to pick \(currentImportType.title) file: \(error.localizedDescription)"
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

// MARK: - Import Type Definition (moved outside of SettingsView for accessibility)
enum ImportType: Hashable {
    case pokerbase, pokerAnalytics, pbt, regroup
    
    var title: String {
        switch self {
        case .pokerbase: return "Pokerbase"
        case .pokerAnalytics: return "Poker Analytics"
        case .pbt: return "Poker Bankroll Tracker"
        case .regroup: return "Regroup"
        }
    }
    
    var fileType: String {
        switch self {
        case .pokerbase: return "CSV"
        case .pokerAnalytics: return "TSV/CSV"
        case .pbt: return "CSV"
        case .regroup: return "CSV"
        }
    }
    
    var color: Color {
        switch self {
        case .pokerbase: return Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
        case .pokerAnalytics: return .cyan
        case .pbt: return .purple
        case .regroup: return .orange
        }
    }
}

// MARK: - Import Options Sheet
struct ImportOptionsSheet: View {
    let onImportSelected: (ImportType) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text("Select Import Format")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 20)
                    
                    Text("Choose the app you want to import your poker session data from:")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 16) {
                        ForEach([ImportType.pokerbase, .pokerAnalytics, .pbt, .regroup], id: \.self) { importType in
                            Button(action: {
                                onImportSelected(importType)
                                dismiss()
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: "tray.and.arrow.down")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(importType.color)
                                        .frame(width: 30)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(importType.title)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundColor(.white)
                                        Text("Import \(importType.fileType) files")
                                            .font(.system(size: 14))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(importType.color.opacity(0.3), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
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

// MARK: - Button Styles
struct ScalePressButtonStyle: ButtonStyle {
    let scaleAmount: CGFloat = 0.95
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

// Helper struct for clarity, though often not strictly necessary for just transparency.
// struct ClearBackground: View { // This helper is no longer used with the new structure
//     var body: some View {
//         Color.clear
//     }
// }

// MARK: - Swipeable Graph Carousel
struct SwipeableGraphCarousel: View {
    let sessions: [Session]
    let bankrollTransactions: [BankrollTransaction]
    @Binding var selectedTimeRange: Int
    let timeRanges: [String]
    @Binding var selectedGraphIndex: Int
    let onChartTouch: (CGPoint, GeometryProxy) -> Void
    let onTouchEnd: () -> Void
    let showTooltip: Bool
    let touchLocation: CGPoint
    let selectedDataPoint: (date: Date, profit: Double)?
    
    @State private var dragOffset: CGFloat = 0
    
    private let graphTypes = ["Bankroll", "Profit", "Monthly"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Swipeable graph container
            TabView(selection: $selectedGraphIndex) {
                // Bankroll Graph (sessions + bankroll adjustments)
                BankrollGraphView(
                    sessions: sessions,
                    bankrollTransactions: bankrollTransactions,
                    selectedTimeRange: selectedTimeRange,
                    timeRanges: timeRanges,
                    onChartTouch: onChartTouch,
                    onTouchEnd: onTouchEnd,
                    showTooltip: showTooltip,
                    touchLocation: touchLocation,
                    selectedDataPoint: selectedDataPoint
                )
                .tag(0)
                
                // Profit Graph (sessions only)
                ProfitGraphView(
                    sessions: sessions,
                    selectedTimeRange: selectedTimeRange,
                    timeRanges: timeRanges,
                    onChartTouch: onChartTouch,
                    onTouchEnd: onTouchEnd,
                    showTooltip: showTooltip,
                    touchLocation: touchLocation,
                    selectedDataPoint: selectedDataPoint
                )
                .tag(1)
                
                // Monthly Profit Bar Chart
                MonthlyProfitBarChart(
                    sessions: sessions,
                    bankrollTransactions: bankrollTransactions,
                    onBarTouch: { monthData in
                        // Handle bar touch to show monthly profit
                        // Could potentially update selectedDataPoint here if needed
                    }
                )
                .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(height: 280)
            
            // Time period selector (only for bankroll and profit graphs)
            if selectedGraphIndex < 2 {
                HStack {
                    ForEach(Array(timeRanges.enumerated()), id: \.element) { index, rangeString in
                        Button(action: {
                            selectedTimeRange = index
                        }) {
                            Text(rangeString)
                                .font(.system(size: 13, weight: selectedTimeRange == index ? .medium : .regular))
                                .foregroundColor(selectedTimeRange == index ? .white : .gray)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(selectedTimeRange == index ? Color.gray.opacity(0.3) : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            
            // Graph type indicators (moved to bottom, after time selectors)
            HStack(spacing: 16) {
                ForEach(Array(graphTypes.enumerated()), id: \.offset) { index, type in
                    Button(action: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            selectedGraphIndex = index
                        }
                    }) {
                        Text(type)
                            .font(.system(size: 13, weight: selectedGraphIndex == index ? .semibold : .regular))
                            .foregroundColor(selectedGraphIndex == index ? .white : .gray)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(selectedGraphIndex == index ? Color.gray.opacity(0.3) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, selectedGraphIndex < 2 ? 12 : 16)
        }
        .animation(.easeInOut(duration: 0.3), value: selectedGraphIndex)
    }
}

// MARK: - Bankroll Graph View
struct BankrollGraphView: View {
    let sessions: [Session]
    let bankrollTransactions: [BankrollTransaction]
    let selectedTimeRange: Int
    let timeRanges: [String]
    let onChartTouch: (CGPoint, GeometryProxy) -> Void
    let onTouchEnd: () -> Void
    let showTooltip: Bool
    let touchLocation: CGPoint
    let selectedDataPoint: (date: Date, profit: Double)?
    
    private func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return sessions.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneYearAgo }
        default: // All
            return sessions
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Y-axis grid lines
                VStack(spacing: 0) {
                    ForEach(0..<5) { _ in
                        Spacer()
                        Divider()
                            .background(Color.gray.opacity(0.1))
                    }
                }
                
                // Background gradient
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
                
                // Combined bankroll chart (sessions + transactions)
                let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
                let filteredTransactions = bankrollTransactions // Include all bankroll transactions
                
                // Combine and sort data points
                let combinedData = (filteredSessions.map { (date: $0.startDate, amount: $0.profit, type: "session") } +
                                  filteredTransactions.map { (date: $0.timestamp, amount: $0.amount, type: "transaction") })
                    .sorted { $0.date < $1.date }
                
                if !combinedData.isEmpty {
                    let cumulativeData = combinedData.reduce(into: [(Date, Double)]()) { result, item in
                        let previousTotal = result.last?.1 ?? 0
                        result.append((item.date, previousTotal + item.amount))
                    }
                    
                    let totalProfit = cumulativeData.last?.1 ?? 0
                    let chartColor = totalProfit >= 0 ? 
                        Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                        Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
                    
                    // Draw chart path
                    ChartPath(
                        dataPoints: cumulativeData,
                        geometry: geometry,
                        color: chartColor,
                        showFill: true
                    )
                }
                
                // Interactive overlay
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onChartTouch(value.location, geometry)
                            }
                            .onEnded { _ in
                                onTouchEnd()
                            }
                    )
                
                // Touch indicator
                if showTooltip {
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
    }
}

// MARK: - Profit Graph View
struct ProfitGraphView: View {
    let sessions: [Session]
    let selectedTimeRange: Int
    let timeRanges: [String]
    let onChartTouch: (CGPoint, GeometryProxy) -> Void
    let onTouchEnd: () -> Void
    let showTooltip: Bool
    let touchLocation: CGPoint
    let selectedDataPoint: (date: Date, profit: Double)?
    
    private func filteredSessionsForTimeRange(_ timeRangeIndex: Int) -> [Session] {
        let now = Date()
        let calendar = Calendar.current
        
        switch timeRangeIndex {
        case 0: // 24H
            let oneDayAgo = calendar.date(byAdding: .day, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneDayAgo }
        case 1: // 1W
            let oneWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneWeekAgo }
        case 2: // 1M
            let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneMonthAgo }
        case 3: // 6M
            let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: now) ?? now
            return sessions.filter { $0.startDate >= sixMonthsAgo }
        case 4: // 1Y
            let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return sessions.filter { $0.startDate >= oneYearAgo }
        default: // All
            return sessions
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Y-axis grid lines
                VStack(spacing: 0) {
                    ForEach(0..<5) { _ in
                        Spacer()
                        Divider()
                            .background(Color.gray.opacity(0.1))
                    }
                }
                
                // Background gradient
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
                
                // Profit-only chart (sessions only)
                let filteredSessions = filteredSessionsForTimeRange(selectedTimeRange)
                
                if !filteredSessions.isEmpty {
                    let sortedSessions = filteredSessions.sorted { $0.startDate < $1.startDate }
                    let cumulativeData = sortedSessions.reduce(into: [(Date, Double)]()) { result, session in
                        let previousTotal = result.last?.1 ?? 0
                        result.append((session.startDate, previousTotal + session.profit))
                    }
                    
                    let totalProfit = cumulativeData.last?.1 ?? 0
                    let chartColor = totalProfit >= 0 ? 
                        Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                        Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
                    
                    // Draw chart path
                    ChartPath(
                        dataPoints: cumulativeData,
                        geometry: geometry,
                        color: chartColor,
                        showFill: true
                    )
                }
                
                // Interactive overlay
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                onChartTouch(value.location, geometry)
                            }
                            .onEnded { _ in
                                onTouchEnd()
                            }
                    )
                
                // Touch indicator
                if showTooltip {
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
    }
}

// MARK: - Monthly Profit Bar Chart
struct MonthlyProfitBarChart: View {
    let sessions: [Session]
    let bankrollTransactions: [BankrollTransaction]
    let onBarTouch: (String) -> Void
    
    @State private var selectedBarIndex: Int? = nil
    
    private func barHeight(for profit: Double, isPositive: Bool, positiveMax: Double, negativeMin: Double, maxAbsValue: Double, zeroLineY: CGFloat, geometryHeight: CGFloat) -> CGFloat {
        guard maxAbsValue > 0 else { return 0 }
        
        if isPositive {
            return (profit / positiveMax) * (zeroLineY - 30)
        } else {
            return (abs(profit) / abs(negativeMin)) * (geometryHeight - 30 - zeroLineY)
        }
    }
    
    private func barColor(isPositive: Bool) -> Color {
        return isPositive ? 
            Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
            Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0))
    }
    
    private var monthlyData: [(String, Double)] {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yy"
        
        // Get last 12 months
        var months: [Date] = []
        for i in 0..<12 {
            if let date = calendar.date(byAdding: .month, value: -i, to: now) {
                months.append(date)
            }
        }
        months.reverse()
        
        return months.map { month in
            let monthProfit = sessions.filter { session in
                calendar.isDate(session.startDate, equalTo: month, toGranularity: .month)
            }.reduce(0) { $0 + $1.profit }
            
            let bankrollProfit = bankrollTransactions.filter { transaction in
                calendar.isDate(transaction.timestamp, equalTo: month, toGranularity: .month)
            }.reduce(0) { $0 + $1.amount }
            
            return (formatter.string(from: month), monthProfit + bankrollProfit)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let data = monthlyData
            let maxValue = data.map { abs($0.1) }.max() ?? 1
            let centerY = geometry.size.height / 2
            let availableHeight = centerY - 25 // Leave space for labels
            let barWidth: CGFloat = 24 // Fixed width for consistency
            let totalBarsWidth = CGFloat(data.count) * barWidth
            let totalSpacing = geometry.size.width - totalBarsWidth - 32 // 16 padding on each side
            let spacing = totalSpacing / CGFloat(max(1, data.count - 1))
            
            ZStack {
                // Grid lines for reference
                VStack(spacing: 0) {
                    ForEach(0..<3) { i in
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 0.5)
                        if i < 2 { Spacer() }
                    }
                }
                .padding(.vertical, 15)
                
                // Central zero line (emphasized)
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.clear,
                                Color.gray.opacity(0.6),
                                Color.gray.opacity(0.8),
                                Color.gray.opacity(0.6),
                                Color.clear
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 2)
                    .position(x: geometry.size.width / 2, y: centerY)
                    .shadow(color: Color.gray.opacity(0.3), radius: 1, y: 0)
                
                // Bars with perfect alignment
                HStack(spacing: 0) {
                    ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                        let (month, profit) = item
                        let isPositive = profit >= 0
                        let barHeight = maxValue > 0 ? min(abs(profit) / maxValue * availableHeight, availableHeight) : 0
                        let barColor = barColor(isPositive: isPositive)
                        
                        VStack(spacing: 0) {
                            // Top section (positive values)
                            ZStack(alignment: .bottom) {
                                // Spacer to maintain layout
                                Color.clear
                                    .frame(height: availableHeight)
                                
                                // Positive bar
                                if isPositive && barHeight > 0 {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: barColor.opacity(0.3), location: 0),
                                                    .init(color: barColor.opacity(0.7), location: 0.3),
                                                    .init(color: barColor, location: 0.7),
                                                    .init(color: barColor.opacity(0.9), location: 1)
                                                ]),
                                                startPoint: .bottom,
                                                endPoint: .top
                                            )
                                        )
                                        .frame(width: barWidth, height: barHeight)
                                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                                        .shadow(color: barColor.opacity(0.4), radius: 3, x: 0, y: -2)
                                        .overlay(
                                            // Highlight effect
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.white.opacity(0.3),
                                                            Color.clear
                                                        ]),
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: barWidth * 0.7, height: barHeight * 0.4)
                                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                                                .offset(y: -barHeight * 0.3)
                                        )
                                        .scaleEffect(selectedBarIndex == index ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedBarIndex)
                                }
                            }
                            
                            // Center divider (zero line space)
                            Rectangle()
                                .fill(Color.clear)
                                .frame(height: 4)
                            
                            // Bottom section (negative values)
                            ZStack(alignment: .top) {
                                // Spacer to maintain layout
                                Color.clear
                                    .frame(height: availableHeight)
                                
                                // Negative bar
                                if !isPositive && barHeight > 0 {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: barColor.opacity(0.9), location: 0),
                                                    .init(color: barColor, location: 0.3),
                                                    .init(color: barColor.opacity(0.7), location: 0.7),
                                                    .init(color: barColor.opacity(0.3), location: 1)
                                                ]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .frame(width: barWidth, height: barHeight)
                                        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6))
                                        .shadow(color: barColor.opacity(0.4), radius: 3, x: 0, y: 2)
                                        .overlay(
                                            // Highlight effect
                                            Rectangle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color.clear,
                                                            Color.white.opacity(0.2)
                                                        ]),
                                                        startPoint: .top,
                                                        endPoint: .bottom
                                                    )
                                                )
                                                .frame(width: barWidth * 0.7, height: barHeight * 0.4)
                                                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4))
                                                .offset(y: barHeight * 0.3)
                                        )
                                        .scaleEffect(selectedBarIndex == index ? 1.05 : 1.0)
                                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedBarIndex)
                                }
                            }
                        }
                        .frame(width: barWidth)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                selectedBarIndex = selectedBarIndex == index ? nil : index
                            }
                            onBarTouch(month)
                        }
                        
                        // Add spacing except after last item
                        if index < data.count - 1 {
                            Spacer()
                                .frame(width: spacing)
                        }
                    }
                }
                .padding(.horizontal, 16)
                
                // Month labels with better positioning
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                            Text(item.0.split(separator: " ").first ?? "")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.gray.opacity(0.8))
                                .frame(width: barWidth)
                                .multilineTextAlignment(.center)
                            
                            // Add spacing except after last item
                            if index < data.count - 1 {
                                Spacer()
                                    .frame(width: spacing)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                
                // Value labels on hover/selection
                if let selectedIndex = selectedBarIndex {
                    let selectedData = data[selectedIndex]
                    VStack(spacing: 4) {
                        Text(selectedData.0)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        Text("$\(Int(selectedData.1).formattedWithCommas)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(selectedData.1 >= 0 ? 
                                          Color(UIColor(red: 140/255, green: 255/255, blue: 38/255, alpha: 1.0)) : 
                                          Color(UIColor(red: 246/255, green: 68/255, blue: 68/255, alpha: 1.0)))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Material.ultraThinMaterial)
                                .opacity(0.9)
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        }
                    )
                    .position(x: geometry.size.width / 2, y: 30)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }
}



// MARK: - Chart Path Helper
struct ChartPath: View {
    let dataPoints: [(Date, Double)]
    let geometry: GeometryProxy
    let color: Color
    let showFill: Bool
    
    var body: some View {
        ZStack {
            if showFill {
                // Fill area
                Path { path in
                    guard !dataPoints.isEmpty else { return }
                    
                    let minProfit = dataPoints.map { $0.1 }.min() ?? 0
                    let maxProfit = max(dataPoints.map { $0.1 }.max() ?? 1, 1)
                    let range = max(maxProfit - minProfit, 1)
                    
                    let stepX = dataPoints.count > 1 ? geometry.size.width / CGFloat(dataPoints.count - 1) : geometry.size.width
                    
                    func getY(_ value: Double) -> CGFloat {
                        let normalized = range == 0 ? 0.5 : (value - minProfit) / range
                        return geometry.size.height * (1 - CGFloat(normalized))
                    }
                    
                    // Start from bottom
                    path.move(to: CGPoint(x: 0, y: geometry.size.height))
                    path.addLine(to: CGPoint(x: 0, y: getY(dataPoints[0].1)))
                    
                    // Draw through all points
                    for i in 1..<dataPoints.count {
                        let x = CGFloat(i) * stepX
                        let y = getY(dataPoints[i].1)
                        
                        let prevX = CGFloat(i-1) * stepX
                        let prevY = getY(dataPoints[i-1].1)
                        
                        let controlPoint1 = CGPoint(x: prevX + stepX/3, y: prevY)
                        let controlPoint2 = CGPoint(x: x - stepX/3, y: y)
                        
                        path.addCurve(to: CGPoint(x: x, y: y), control1: controlPoint1, control2: controlPoint2)
                    }
                    
                    // Close to bottom
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: color.opacity(0.35), location: 0),
                            .init(color: color.opacity(0.15), location: 0.4),
                            .init(color: color.opacity(0.08), location: 0.7),
                            .init(color: Color.clear, location: 1)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            
            // Line path
            Path { path in
                guard !dataPoints.isEmpty else { return }
                
                let minProfit = dataPoints.map { $0.1 }.min() ?? 0
                let maxProfit = max(dataPoints.map { $0.1 }.max() ?? 1, 1)
                let range = max(maxProfit - minProfit, 1)
                
                let stepX = dataPoints.count > 1 ? geometry.size.width / CGFloat(dataPoints.count - 1) : geometry.size.width
                
                func getY(_ value: Double) -> CGFloat {
                    let normalized = range == 0 ? 0.5 : (value - minProfit) / range
                    return geometry.size.height * (1 - CGFloat(normalized))
                }
                
                path.move(to: CGPoint(x: 0, y: getY(dataPoints[0].1)))
                
                for i in 1..<dataPoints.count {
                    let x = CGFloat(i) * stepX
                    let y = getY(dataPoints[i].1)
                    
                    let prevX = CGFloat(i-1) * stepX
                    let prevY = getY(dataPoints[i-1].1)
                    
                    let controlPoint1 = CGPoint(x: prevX + stepX/3, y: prevY)
                    let controlPoint2 = CGPoint(x: x - stepX/3, y: y)
                    
                    path.addCurve(to: CGPoint(x: x, y: y), control1: controlPoint1, control2: controlPoint2)
                }
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        color.opacity(0.9),
                        color,
                        color.opacity(0.95)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: color.opacity(0.4), radius: 4, y: 2)
        }
    }
}






