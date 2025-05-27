import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
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
    @StateObject private var sessionStore: SessionStore
    @StateObject private var handStore: HandStore
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
    
    // Analytics specific state (remains for analyticsDetailContent)
    @State private var selectedTimeRange = 1 // Default to 1W (index 1) for Analytics
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"] // Used by analyticsDetailContent
    
    init(userId: String) {
        self.userId = userId
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }
    
    // Removed ProfileTab enum and tabItems
    
    var body: some View {
        // let selectedTabGreen = Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
        // let deselectedTabGray = Color.white.opacity(0.7)
        // let clearColor = Color.clear

        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top bar with title and settings button
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
                .padding(.bottom, 16)
                .padding(.top, 20) // Added top padding specifically to this HStack
                
                // Profile Card - Always visible
                ProfileCardView(
                    userId: userId,
                    showEdit: $showEdit,
                    showingFollowersSheet: $showingFollowersSheet, // These bindings need to be declared
                    showingFollowingSheet: $showingFollowingSheet  // These bindings need to be declared
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20) // Add some space before cards
                
                // Invisible NavigationLink for programmatic post navigation (if needed at this level)
                // This was for the old tab structure. ActivityContentView now handles its navigation internally
                // when wrapped in NavigationView.
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

                // ScrollView for Navigation Cards
                ScrollView {
                    VStack(spacing: 16) {
                        // Recent Activity Card
                        navigationCard(
                            title: "Recent Activity",
                            iconName: "list.bullet.below.rectangle",
                            baseColor: Color.blue, 
                            action: { showActivityDetailView = true }
                        ) {
                            Text("View your latest posts and interactions.")
                                .font(.plusJakarta(.subheadline)) // Apply Jakarta font
                                .foregroundColor(.white.opacity(0.85))
                        }

                        // Analytics Card
                        navigationCard(
                            title: "Analytics",
                            iconName: "chart.bar.xaxis",
                            baseColor: Color.green, 
                            action: { showAnalyticsDetailView = true }
                        ) {
                            Text("Track your performance stats.")
                                .font(.plusJakarta(.subheadline)) // Apply Jakarta font
                                .foregroundColor(.white.opacity(0.85))
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
                            Text("View and manage your stakes.")
                                .font(.plusJakarta(.subheadline))
                                .foregroundColor(.white.opacity(0.85))
                        }

                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30) // For tab bar space
                    .padding(.top, 3) // Added 3 points of top padding to the VStack of cards
                }
            }
            .padding(.top, 20) // Added top padding to the main VStack
        }
        // Removed .onChange(of: selectedTab)
        .sheet(isPresented: $showEdit) {
            if let profile = userService.currentUserProfile {
                ProfileEditView(profile: profile) { updatedProfile in
                    Task { try? await userService.fetchUserProfile() }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(userId: userId)
        }
        // .sheet(isPresented: $showingPostDetailSheet) // This was for PostDetailView, now handled by NavigationLink in ActivityContentView
        .sheet(isPresented: $showingFollowersSheet) { // Ensure these are declared
            FollowListView(userId: userId, listType: .followers)
        }
        .sheet(isPresented: $showingFollowingSheet) { // Ensure these are declared
            FollowListView(userId: userId, listType: .following)
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
        .navigationBarHidden(true)
        .environmentObject(userService)
        .environmentObject(postService)
        .environmentObject(sessionStore)
        .environmentObject(handStore)
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
            HStack(spacing: 16) {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(baseColor.opacity(0.9))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white) 
                    
                    previewContent()
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(EdgeInsets(top: 17, leading: 20, bottom: 15, trailing: 20))
            // Ensure background doesn't block touches, and contentShape defines the hit area clearly.
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.clear) 
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(baseColor.opacity(0.25), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 20)) // Apply contentShape after background
            .shadow(color: baseColor.opacity(0.15), radius: 4, x: 0, y: 2) 
        }
        .buttonStyle(PlainButtonStyle()) // PlainButtonStyle is important for custom button interactions
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
    
    // Content for Analytics Detail View (extracted from old tabContent)
    @ViewBuilder
    private func analyticsDetailContent() -> some View {
        // This ScrollView will be part of the NavigationView in fullScreenCover
        ScrollView {
            VStack(spacing: 20) {
                // Bankroll section with past month profit/loss indicator
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bankroll")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("$\(Int(totalBankroll).formattedWithCommas)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
        
                    HStack(spacing: 4) {
                        // Get profit from selected time range instead of hardcoded month
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
                        
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                
                // Chart display with time selectors at bottom
                VStack(spacing: 10) {
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
                                    chartColor,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                                )
                                .shadow(color: chartColor.opacity(0.3), radius: 3, y: 1)
                                
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
                                        gradient: Gradient(colors: [
                                            chartColor.opacity(0.3),
                                            chartColor.opacity(0.05)
                                        ]),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        }
                        .frame(height: 220)
                        
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
                .padding(.top, 10) // Add some space above the chart section
                
                // Stats cards in grid layout
                Text("MORE STATS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20) // Increased top padding
                
                VStack(spacing: 12) {
                    // Win Rate
                    HStack {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                                .frame(width: 44, height: 44)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(winRate) / 100)
                                .stroke(
                                    Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round) // Added lineCap
                                )
                                .frame(width: 44, height: 44)
                                .rotationEffect(.degrees(-90))
                            
                            Text("\(Int(winRate))%")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Win Rate")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    // Average Profit, Best Session, Total Sessions
                    VStack(spacing: 12) {
                        // Average Profit
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.15)))
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .font(.system(size: 12))
                            }
                            
                            Text("Average Profit")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("$\(Int(averageProfit).formattedWithCommas)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("/session")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                        
                        // Best Session
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.15))
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: "star.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 12))
                            }
                            
                            Text("Best Session")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("$\(Int(bestSession?.profit ?? 0).formattedWithCommas)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Profit")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                        
                        // Total Sessions
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.15))
                                    .frame(width: 24, height: 24)
                                
                                Image(systemName: "calendar")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                            }
                            
                            Text("Total Sessions")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Text("\(totalSessions)")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Played")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20) // This was applying to the VStack of stats, correct
                }
            }
            .padding(.bottom, 30) // Overall padding for the ScrollView content
            .background(AppBackgroundView().ignoresSafeArea()) // Ensure background matches
        }
        .background(AppBackgroundView().ignoresSafeArea()) // Match app background
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
                                    placeholderAvatar(size: 60)
                                }
                            }
                        } else {
                            placeholderAvatar(size: 60)
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
    
    // Helper for placeholder avatar
    @ViewBuilder
    private func placeholderAvatar(size: CGFloat) -> some View {
        Circle().fill(Color.gray.opacity(0.2))
            .frame(width: size, height: size)
            .overlay(Image(systemName: "person.fill").foregroundColor(.gray).font(.system(size: size * 0.4)))
            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
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
                .padding(.top, 50) // Added 40 points of top padding to the ScrollView
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
    @State private var showDeleteConfirmation = false
    @State private var showFinalDeleteConfirmation = false
    @State private var deleteError: String? = nil
    @State private var isDeleting = false
    @State private var pushNotificationsEnabled: Bool = true // Added for push notification toggle
    
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




