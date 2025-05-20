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
    @StateObject private var sessionStore: SessionStore // Keep for analytics data
    @StateObject private var handStore: HandStore     // Keep for analytics data
    @EnvironmentObject private var postService: PostService // Added for recent activity
    @State private var showEdit = false // State for showing edit profile sheet
    @State private var showSettings = false // State for showing settings sheet
    @State private var selectedPostForNavigation: Post? = nil // For programmatic post navigation
    @State private var showingPostDetailSheet: Bool = false // For showing post detail sheet
    @State private var showingFollowersSheet: Bool = false // New: For showing followers sheet
    @State private var showingFollowingSheet: Bool = false // New: For showing following sheet
    
    // Changed to reflect the new tab structure under profile
    @State private var selectedTab: ProfileTab = .activity
    @State private var selectedTimeRange = 1 // Default to 1W (index 1) for Analytics
    private let timeRanges = ["24H", "1W", "1M", "6M", "1Y", "All"]
    
    private let tabItems: [(title: String, tab: ProfileTab)] = [
        (title: "Recent", tab: .activity),
        (title: "Analytics", tab: .analytics),
        (title: "Hands", tab: .hands),
        (title: "Sessions", tab: .sessions)
    ]
    
    init(userId: String) {
        self.userId = userId
        _sessionStore = StateObject(wrappedValue: SessionStore(userId: userId))
        _handStore = StateObject(wrappedValue: HandStore(userId: userId))
    }
    
    // Changed from ProfileViewType to ProfileTab to better reflect the new structure
    enum ProfileTab {
        case activity
        case analytics
        case hands
        case sessions
    }
    
    var body: some View {
        let selectedTabGreen = Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
        let deselectedTabGray = Color.white.opacity(0.7)
        let clearColor = Color.clear

        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            Group {
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                    
                    // Profile Card - Always visible
                    ProfileCardView(
                        userId: userId,
                        showEdit: $showEdit,
                        showingFollowersSheet: $showingFollowersSheet,
                        showingFollowingSheet: $showingFollowingSheet
                    )
                    .padding(.horizontal, 16)
                    
                    // Tab bar under profile card
                    HStack(spacing: 0) {
                        ForEach(tabItems, id: \.tab) { item in
                            self.makeTabButton(
                                title: item.title,
                                representingTab: item.tab,
                                selectedColor: selectedTabGreen,
                                deselectedColor: deselectedTabGray,
                                indicatorClearColor: clearColor
                            )
                        }
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    .background(
                Rectangle()
                            .fill(Color.clear)
                    .frame(height: 1)
                    )
                    
                    // Invisible NavigationLink for programmatic post navigation
                    // Placed here to be part of the main VStack and ScrollView hierarchy
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
                        .frame(width: 0, height: 0) // Ensure it takes no space and is not focusable
                    }

                    // Content based on selected tab handled by helper
                    tabContent()
                }
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab == .activity {
                print("[ProfileView.onChange] Activity tab selected. Checking if posts need fetching for userId: \(userId).")
                print("[ProfileView.onChange] Current postService.posts count: \(postService.posts.count)")
                if let firstPostUserId = postService.posts.first?.userId {
                    print("[ProfileView.onChange] First post in service is for userId: \(firstPostUserId)")
                }
                
                if postService.posts.isEmpty || postService.posts.first?.userId != userId {
                    Task {
                        print("[ProfileView.onChange] Condition met. Fetching posts for userId: \(userId). Current post count: \(postService.posts.count)")
                        do {
                            try await postService.fetchPosts(forUserId: userId)
                            print("[ProfileView.onChange] Post fetching completed. New postService.posts count: \(postService.posts.count)")
                        } catch {
                            print("[ProfileView.onChange] Error fetching posts for userId \(userId): \(error)")
                        }
                    }
                } else {
                    print("[ProfileView.onChange] Posts already loaded for userId: \(userId) or service has other posts. Count: \(postService.posts.count)")
                }
            } else if newTab == .sessions {
                print("[ProfileView.onChange] Sessions tab selected. Checking if sessions need fetching for userId: \(userId).")
                print("[ProfileView.onChange] Current sessionStore.sessions count: \(sessionStore.sessions.count)")
                if sessionStore.sessions.isEmpty { 
                     Task {
                         print("[ProfileView.onChange] Condition met. Fetching sessions for userId: \(userId).")
                         sessionStore.fetchSessions() // This is synchronous, updates will publish
                         print("[ProfileView.onChange] sessionStore.fetchSessions() called. New count: \(sessionStore.sessions.count)") // Note: fetchSessions itself is async internally with listeners
                     }
                }
            } else if newTab == .analytics {
                print("[ProfileView.onChange] Analytics tab selected. Checking if sessions need fetching for userId: \(userId).")
                print("[ProfileView.onChange] Current sessionStore.sessions count: \(sessionStore.sessions.count)")
                 if sessionStore.sessions.isEmpty { 
                     Task {
                         print("[ProfileView] Fetching sessions for Analytics tab, userId: \(userId)")
                         sessionStore.fetchSessions()
                     }
                 }
            }
        }
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
        .sheet(isPresented: $showingPostDetailSheet) {
            if let post = selectedPostForNavigation {
                PostDetailView(post: post, userId: userId)
            }
        }
        .sheet(isPresented: $showingFollowersSheet) {
            FollowListView(userId: userId, listType: .followers)
        }
        .sheet(isPresented: $showingFollowingSheet) {
            FollowListView(userId: userId, listType: .following)
        }
        .navigationBarHidden(true)
        .environmentObject(userService) 
        .environmentObject(postService)
        .environmentObject(sessionStore) 
        .environmentObject(handStore)
        .onAppear {
            // Fetch user profile on appear
            if userService.currentUserProfile == nil {
                Task {
                    try? await userService.fetchUserProfile()
                }
            }
            // Initial fetch for posts if the default tab is .activity
            if selectedTab == .activity {
                print("[ProfileView.onAppear] Initial tab is .activity. Fetching posts for userId: \(userId).")
                // Ensure we are calling the correct fetchPosts that updates ActivityContentView's source (postService.posts)
                Task {
                    do {
                        // This fetch should update postService.posts, which ActivityContentView observes
                        try await postService.fetchPosts(forUserId: userId) 
                        print("[ProfileView.onAppear] Initial post fetch completed. Post count in service: \(postService.posts.count)")
                    } catch {
                        print("[ProfileView.onAppear] Error in initial post fetch: \(error)")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func makeTabButton(title: String, representingTab: ProfileTab, selectedColor: Color, deselectedColor: Color, indicatorClearColor: Color) -> some View {
        let isSelected = (representingTab == self.selectedTab)

        Button(action: {
            withAnimation {
                self.selectedTab = representingTab
            }
        }) {
            VStack(spacing: 8) {
                let textWeight: Font.Weight = isSelected ? .semibold : .medium
                Text(title)
                    .font(.system(size: 15, weight: textWeight))
                    .foregroundColor(isSelected ? selectedColor : deselectedColor)

                Rectangle()
                    .fill(isSelected ? selectedColor : indicatorClearColor) // Indicator uses selectedColor when active
                    .frame(height: 3)
                    .cornerRadius(1.5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Analytics Helper Properties (Unchanged)
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
    
    // Content based on selected tab handled by helper
    @ViewBuilder
    private func tabContent() -> some View {
        Group {
            if selectedTab == .activity {
                ActivityContentView(userId: userId, selectedPostForNavigation: $selectedPostForNavigation, showingPostDetailSheet: $showingPostDetailSheet)
            } else if selectedTab == .analytics {
                // Analytics content
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
                                        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                        Color.red)
                                
                                Text("$\(abs(Int(timeRangeProfit)).formattedWithCommas)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(timeRangeProfit >= 0 ? 
                                        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                        Color.red)
                                
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
                                        let selectedTimeRangeProfit = selectedSessions.reduce(0) { $0 + $1.profit }
                                        let isProfit = selectedTimeRangeProfit >= 0
                                        let chartColor = isProfit ? 
                                            Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                            Color.red
                                        
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
                                            let maxProfit = max(cumulativeProfit.max() ?? 1, 1)
                                            let range = max(maxProfit - minProfit, 1)
                                            
                                            // Draw the path
                                            let step = geometry.size.width / CGFloat(cumulativeProfit.count - 1)
                                            
                                            // Function to get Y position
                                            func getY(_ value: Double) -> CGFloat {
                                                let normalized = (value - minProfit) / range
                                                return geometry.size.height * (1 - CGFloat(normalized))
                                            }
                                            
                                            // Start path
                                            path.move(to: CGPoint(x: 0, y: getY(cumulativeProfit[0])))
                                            
                                            // Draw lines to each point
                                            for i in 1..<cumulativeProfit.count {
                                                let x = CGFloat(i) * step
                                                let y = getY(cumulativeProfit[i])
                                                
                                                // Smooth curve
                                                if i > 0 {
                                                    let prevX = CGFloat(i-1) * step
                                                    let prevY = getY(cumulativeProfit[i-1])
                                                    
                                                    let controlPoint1 = CGPoint(x: prevX + step/3, y: prevY)
                                                    let controlPoint2 = CGPoint(x: x - step/3, y: y)
                                                    
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
                                            let step = geometry.size.width / CGFloat(cumulativeProfit.count - 1)
                                            
                                            // Function to get Y position
                                            func getY(_ value: Double) -> CGFloat {
                                                let normalized = (value - minProfit) / range
                                                return geometry.size.height * (1 - CGFloat(normalized))
                                            }
                                            
                                            // Start path - bottom left
                                            path.move(to: CGPoint(x: 0, y: geometry.size.height))
                                            
                                            // Bottom left to first data point
                                            path.addLine(to: CGPoint(x: 0, y: getY(cumulativeProfit[0])))
                                            
                                            // Draw curves through all points
                                            for i in 1..<cumulativeProfit.count {
                                                let x = CGFloat(i) * step
                                                let y = getY(cumulativeProfit[i])
                                                
                                                // Smooth curve
                                                if i > 0 {
                                                    let prevX = CGFloat(i-1) * step
                                                    let prevY = getY(cumulativeProfit[i-1])
                                                    
                                                    let controlPoint1 = CGPoint(x: prevX + step/3, y: prevY)
                                                    let controlPoint2 = CGPoint(x: x - step/3, y: y)
                                                    
                                                    path.addCurve(to: CGPoint(x: x, y: y), 
                                                               control1: controlPoint1, 
                                                               control2: controlPoint2)
                                                }
                                            }
                                            
                                            // Last point to bottom right
                                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                                            
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
                                    ForEach(["1H", "24H", "1W", "1M", "6M", "1Y", "All"], id: \.self) { range in
                                        let index = timeRanges.firstIndex(of: range) ?? 0
                                        Button(action: {
                                            selectedTimeRange = index
                                        }) {
                                            Text(range)
                                                .font(.system(size: 13, weight: selectedTimeRange == index ? .medium : .regular))
                                                .foregroundColor(selectedTimeRange == index ? .white : .gray)
                                                .frame(maxWidth: .infinity)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Stats cards in grid layout
                        Text("MORE STATS")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                        
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
                                            lineWidth: 4
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
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 30)
                }
            } else if selectedTab == .hands {
                // Use transparent navigation container to keep background consistent
                TransparentNavigationView(content: HandsTab(handStore: handStore))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    .disabled(false)
                    .allowsHitTesting(true)
            } else if selectedTab == .sessions {
                // Use transparent navigation container for Sessions tab
                TransparentNavigationView(content: SessionsTab(sessionStore: sessionStore))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                    .disabled(false)
                    .allowsHitTesting(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity) // Allow Group to expand
        .padding(.bottom, 30) // Add padding at bottom for tab bar
    }
    
    private func getTimeRangeLabel(for index: Int) -> String {
        switch index {
        case 0: return "Past 24H"
        case 1: return "Past week"
        case 2: return "Past month" 
        case 3: return "Past 6 months"
        case 4: return "Past year"
        case 5: return "All time"
        default: return "Selected period"
        }
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
    @Binding var showingPostDetailSheet: Bool // Added to control sheet presentation

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
                .padding(.bottom, 120) // Extra padding for tab bar
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
        do {
            try Auth.auth().signOut()
            // Directly set auth state to signed out to trigger the welcome screen
            DispatchQueue.main.async {
                // Clear user data first to prevent any state inconsistencies
                authViewModel.userService.currentUserProfile = nil
                // This will directly switch to the WelcomeView through MainCoordinator
                authViewModel.authState = .signedOut
            }
        } catch {
            print("Error signing out: \(error)")
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
            print("Profile image deletion failed: \(error.localizedDescription). Continuing with account deletion.")
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




