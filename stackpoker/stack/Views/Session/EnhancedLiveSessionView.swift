import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct EnhancedLiveSessionView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var postService = PostService()
    @StateObject private var userService = UserService()
    let userId: String
    @ObservedObject var sessionStore: SessionStore
    @StateObject private var cashGameService = CashGameService(userId: Auth.auth().currentUser?.uid ?? "")
    @StateObject private var handStore = HandStore(userId: Auth.auth().currentUser?.uid ?? "")
    @State private var handEntryMinimized = false
    
    // Callback for when a session ends, passing the new session ID
    var onSessionDidEnd: ((_ sessionId: String) -> Void)?
    
    // UI States
    @State private var selectedTab: LiveSessionTab = .session
    @State private var sessionMode: SessionMode = .setup
    @State private var chipAmount = ""
    @State private var noteText = ""
    @State private var handHistoryText = ""
    @State private var feedText = ""
    @State private var buyIn = ""
    @State private var selectedGame: CashGame? = nil
    @State private var showingAddGame = false
    @State private var showingStackUpdateSheet = false
    @State private var showingHandHistorySheet = false
    @State private var showingExitAlert = false
    @State private var showingCashoutPrompt = false
    @State private var isLoadingSave = false
    @State private var cashoutAmount = ""
    
    // Data model values - initialized onAppear
    @State private var chipUpdates: [ChipStackUpdate] = []
    @State private var handHistories: [HandHistoryEntry] = []
    @State private var notes: [String] = []
    @State private var sessionPosts: [Post] = []
    @State private var isLoadingSessionPosts = false
    
    // Recent updates feed (chip updates, notes, hands)
    @State private var recentUpdates: [UpdateItem] = []
    
    // Single lightweight struct for feed display
    private struct UpdateItem: Identifiable {
        enum Kind { case chip, note, hand, sessionStart }
        let id: String
        let kind: Kind
        let title: String
        let description: String
        let timestamp: Date
    }
    
    // New states
    @State private var showingHandWizard = false
    
    // Add a state variable for minimizing the entire session
    @State private var sessionMinimized = false
    
    // New states for share to feed
    @State private var showingPostEditor = false
    @State private var showingNoProfileAlert = false
    
    // Add back the share to feed state variables (put them before the showingPostEditor declaration)
    @State private var shareToFeedContent = ""
    @State private var shareToFeedIsHand = false
    @State private var shareToFeedHandData: ParsedHandHistory? = nil
    @State private var shareToFeedUpdateId: String? = nil
    
    // Add back the rebuy state variables
    @State private var rebuyAmount = ""
    @State private var showingRebuySheet = false
    
    // Add new state variables
    @State private var shareToFeedIsNote = false
    @State private var shareToFeedIsChipUpdate = false
    
    // Add state for tracking selected post
    @State private var selectedPost: Post? = nil
    
    // Add state variable for tracking whether the edit buy-in section is expanded
    @State private var showEditBuyIn = false
    @State private var editBuyInAmount = ""
    
    // New states
    @State private var showingShareToFeedPrompt = false
    @State private var sessionDetails: (buyIn: Double, cashout: Double, profit: Double, duration: String, gameName: String, stakes: String, sessionId: String)? = nil
    @State private var showingSimpleNoteEditor = false // New state for presenting the note editor
    @State private var showingNewHandEntry = false // New state for presenting NewHandEntryView
    @State private var completedSessionToShowInSheet: Session? = nil // For sheet presentation
    @State private var showSessionDetailSheet = false // Controls sheet presentation
    
    // MARK: - Enum Definitions
    enum LiveSessionTab {
        case session
        case notes
        case hands
        case posts
    }
    
    enum SessionMode {
        case setup    // Initial game selection and buy-in
        case active   // Session is running
        case paused   // Session is paused
        case ending   // Session is ending, entering cashout
    }
    
    // MARK: - Computed Properties
    
    private var sessionTitle: String {
        if sessionMode == .setup {
            return "New Session"
        } else {
            return "\(sessionStore.liveSession.stakes) @ \(sessionStore.liveSession.gameName)"
        }
    }
    
    private var statusText: String {
        return sessionStore.liveSession.isActive ? "LIVE" : "PAUSED"
    }
    
    private var formattedElapsedTime: (hours: Int, minutes: Int, seconds: Int) {
        let totalSeconds = Int(sessionStore.liveSession.elapsedTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return (hours, minutes, seconds)
    }
    
    private var allChipAmounts: [Double] {
        return sessionStore.enhancedLiveSession.allChipAmounts
    }
    
    private var currentProfit: Double {
        // Get the current chip amount
        let currentStack = sessionStore.enhancedLiveSession.currentChipAmount
        // Get the initial buy-in amount
        let initialBuyIn = sessionStore.liveSession.buyIn
        
        // Calculate the correct profit by subtracting total buy-in from current stack
        return currentStack - initialBuyIn
    }
    
    private var accentColor: Color {
        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))
    }
    
    private var statusColor: Color {
        sessionStore.liveSession.isActive ? accentColor : Color.orange
    }
    
    // MARK: - Main Body
    
    var body: some View {
        NavigationView {
            mainContent
        }
    }
    
    // MARK: - Content Views
    
    private var mainContent: some View {
        ZStack {
            // Base background
            AppBackgroundView()
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                if sessionMode == .setup {
                    setupView
                } else {
                    activeSessionView
                }
            }
            .opacity(sessionMinimized ? 0 : 1)
            
            // Floating control
            if sessionMinimized {
                minimizedControl
            }
        }
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .accentColor(.white)
        .onAppear(perform: handleOnAppear)
        .sheet(isPresented: $showingStackUpdateSheet) {
            stackUpdateSheet
        }
        .sheet(isPresented: $showingHandHistorySheet) {
            handHistorySheet
        }
        .alert("Exit Session?", isPresented: $showingExitAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Exit Without Saving", role: .destructive) {
                dismiss()
            }
            Button("End & Cashout") {
                showingCashoutPrompt = true
            }
        } message: {
            Text("What would you like to do with your active session?")
        }
        .alert("End Session", isPresented: $showingCashoutPrompt) {
            TextField("$", text: $cashoutAmount)
                .keyboardType(.decimalPad)
            
            Button("Cancel", role: .cancel) { }
            Button("End Session") {
                if let amount = Double(cashoutAmount), amount >= 0 {
                    endSession(cashout: amount)
                }
            }
        } message: {
            Text("Enter your final chip count to end the session")
        }
        .alert("Share Session Result", isPresented: $showingShareToFeedPrompt) {
            Button("Not Now", role: .cancel) {
                dismiss()
            }
            Button("Share to Feed") {
                if let details = sessionDetails, userService.currentUserProfile != nil {
                    // Create session summary content
                    let profitText = details.profit >= 0 ? "+$\(Int(details.profit))" : "-$\(Int(abs(details.profit)))"
                    let content = """
                    Session at \(details.gameName) (\(details.stakes))
                    Duration: \(details.duration)
                    Buy-in: $\(Int(details.buyIn))
                    Cashout: $\(Int(details.cashout))
                    Profit: \(profitText)
                    """
                    
                    // Show the post editor with session details
                    shareToFeedContent = content
                    shareToFeedIsHand = false
                    shareToFeedHandData = nil
                    shareToFeedUpdateId = nil
                    shareToFeedIsNote = false
                    shareToFeedIsChipUpdate = false
                    showingPostEditor = true
                } else {
                    dismiss()
                }
            }
        } message: {
            if let details = sessionDetails {
                let profitText = details.profit >= 0 ? "+$\(Int(details.profit))" : "-$\(Int(abs(details.profit)))"
                Text("Share your \(profitText) session result with your followers?")
            } else {
                Text("Would you like to share your session result?")
            }
        }
        .sheet(isPresented: $showingPostEditor, onDismiss: {
            // When the post editor dismisses, also dismiss this view
            dismiss()
        }) {
            postEditorSheet
        }
        .sheet(isPresented: $showingRebuySheet) {
            rebuyView
        }
        .sheet(isPresented: $showingHandWizard) {
            NavigationView {
                NewHandEntryView(sessionId: sessionStore.liveSession.id)
                    .environmentObject(handStore)
            }
            .onDisappear {
                checkForNewHands()
            }
        }
        .alert("Sign In Required", isPresented: $showingNoProfileAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You need to sign in to share content to the feed.")
        }
        .sheet(isPresented: $showSessionDetailSheet) { // Sheet for SessionDetailView
            if let session = completedSessionToShowInSheet {
                NavigationView { // Embed in NavigationView for title and dismiss button
                    SessionDetailView(session: session)
                        .navigationBarBackButtonHidden(true)
                        .toolbar { // Add a dismiss button to the SessionDetailView sheet
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    showSessionDetailSheet = false
                                    // Now dismiss EnhancedLiveSessionView after detail sheet is closed
                                    self.dismiss() 
                                }
                                .foregroundColor(.white)
                            }
                        }
                }
            }
        }
    }
    
    private var activeSessionView: some View {
        ZStack(alignment: .bottom) { // Align content to the bottom for the tab bar
            // TabView takes up the main space
            TabView(selection: $selectedTab) {
                sessionTabView
                    .tag(LiveSessionTab.session)
                    .contentShape(Rectangle())
                
                notesTabView
                    .tag(LiveSessionTab.notes)
                    .contentShape(Rectangle())
                
                handsTabView
                    .tag(LiveSessionTab.hands)
                    .contentShape(Rectangle())
                
                postsTabView
                    .tag(LiveSessionTab.posts)
                    .contentShape(Rectangle())
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            // Add bottom padding to the TabView itself to make space for the floating tab bar
            // This value should be roughly the height of the customTabBar + its container's bottom padding
            .padding(.bottom, 80) // Example: 50 for tab bar + 15 for top padding + 15 for bottom container padding
            
            // Container for the floating tab bar
            customTabBar
                .padding(.horizontal, 20) // Padding from screen edges
                .padding(.bottom, 50) // Padding from the very bottom of the screen (adjust for safe area if needed)
        }
    }
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Session", icon: "timer", tab: .session)
            tabButton(title: "Notes", icon: "note.text", tab: .notes)
            tabButton(title: "Hands", icon: "suit.spade", tab: .hands)
            tabButton(title: "Posts", icon: "text.bubble", tab: .posts)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            // Use a Material blur for a modern floating effect
            .ultraThinMaterial
        )
        .clipShape(Capsule()) // Rounded capsule shape for the floating bar
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5) // Soft shadow
    }
    
    private var minimizedControl: some View {
        GeometryReader { geometry in
            SessionMinimizedFloatingControl(
                gameName: sessionStore.liveSession.gameName,
                statusColor: statusColor,
                profit: currentProfit,
                onTap: { sessionMinimized = false }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .edgesIgnoringSafeArea(.bottom)
        }
    }
    
    private var stackUpdateSheet: some View {
        StackUpdateSheet(
            isPresented: $showingStackUpdateSheet,
            chipAmount: $chipAmount,
            noteText: $noteText,
            onSubmit: handleStackUpdate
        )
    }
    
    private var handHistorySheet: some View {
        HandHistoryInputSheet(
            isPresented: $showingHandHistorySheet,
            handText: $handHistoryText,
            onSubmit: handleHandHistoryInput
        )
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) { titleView }
        ToolbarItem(placement: .navigationBarLeading) { leadingButton }
        
        if selectedTab == .notes {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingSimpleNoteEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(accentColor)
                }
            }
        } else if selectedTab == .hands {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingNewHandEntry = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(accentColor)
                }
            }
        }
    }
    
    private var titleView: some View {
        Group {
            if sessionMode == .setup {
                Text(sessionTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            } else {
                VStack(spacing: 2) {
                    Text(sessionTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        
                        Text(statusText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                    .opacity(0.8)
                }
            }
        }
    }
    
    private var leadingButton: some View {
        Button(action: handleLeadingButtonTap) {
            Image(systemName: sessionMode == .setup ? "xmark" : "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleLeadingButtonTap() {
        if sessionMode == .setup {
            dismiss()
        } else if sessionMode == .ending {
            sessionMode = sessionStore.liveSession.isActive ? .active : .paused
        } else {
            // Now just dismiss the view instead of minimizing
            dismiss()
        }
    }
    
    private func handleOnAppear() {
        // Check if there's an active session first
        if sessionStore.liveSession.buyIn > 0 {
            // Determine session mode more directly
            sessionMode = sessionStore.liveSession.isActive ? .active : .paused
            
            // If it's a new session or the initial buy-in hasn't been recorded as a chip update yet
            if sessionStore.enhancedLiveSession.chipUpdates.isEmpty && sessionStore.liveSession.buyIn > 0 {
                 sessionStore.updateChipStack(amount: sessionStore.liveSession.buyIn, note: "Initial buy-in")
            }
            // Initialize data from session store's enhanced session
            updateLocalDataFromStore() // This will now include Session Started and the initial chip update if just added
            
            loadSessionPosts()
            
            // Check for hands associated with this session
            Task {
                // Wait a moment for hands to initialize
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Check for new hands when view appears
                await MainActor.run {
                    checkForNewHands()
                }
            }
        } else {
            // No active session, show setup
            sessionMode = .setup
            loadCashGames()
        }
        
        // Log the state for debugging
        print("Enhanced Live Session View appeared")
        print("Session mode: \(sessionMode)")
        print("Current chip updates: \(sessionStore.enhancedLiveSession.chipUpdates.count)")
        
        // Ensure user profile is loaded for posting
        Task {
            try? await userService.fetchUserProfile()
        }
    }
    
    // MARK: - Setup View
    
    // View for setting up a new session
    private var setupView: some View {
        ZStack {
            // Use AppBackgroundView as background
            AppBackgroundView()
                .ignoresSafeArea()
                
            ScrollView {
                VStack(spacing: 32) {
                    // Add top padding for transparent navigation bar
                    Spacer()
                        .frame(height: 50)
                    
                    // Game Selection Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Select Game")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        if cashGameService.cashGames.isEmpty {
                            HStack {
                                Text("No games added. Tap to add a new game.")
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                
                                Spacer()
                                
                                Button(action: { showingAddGame = true }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Circle().fill(Color.gray.opacity(0.3)))
                                }
                            }
                            .padding(.vertical, 20)
                        } else {
                            // Game selection grid with consistent sizing
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                ForEach(cashGameService.cashGames) { game in
                                    GameCard(
                                        title: game.name,
                                        subtitle: game.stakes,
                                        isSelected: selectedGame?.id == game.id
                                    )
                                    .onTapGesture {
                                        selectedGame = game
                                    }
                                }
                                
                                // Add new game card (matches game card style)
                                Button(action: { showingAddGame = true }) {
                                    HStack {
                                        Image(systemName: "plus")
                                            .font(.system(size: 18))
                                            .foregroundColor(.white)
                                        
                                        Text("Add Game")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .frame(height: 50)
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                            )
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Buy-in Section
                    if selectedGame != nil {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Buy-in Amount")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                            
                            HStack {
                                Text("$")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.gray)
                                
                                TextField("0", text: $buyIn)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Start Button
                    if selectedGame != nil {
                        Button(action: startSession) {
                            Text("Start Session")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(
                                    RoundedRectangle(cornerRadius: 27)
                                        .fill(buyIn.isEmpty ? Color.gray.opacity(0.3) : Color.gray.opacity(0.5))
                                        .background(.ultraThinMaterial)
                                        .clipShape(RoundedRectangle(cornerRadius: 27))
                                )
                        }
                        .disabled(buyIn.isEmpty)
                        .padding(.horizontal)
                        .padding(.top, 16)
                    }
                    
                    Spacer()
                }
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showingAddGame) {
            AddCashGameView(cashGameService: cashGameService)
        }
    }
    
    // Game selection card
    private struct GameCard: View {
        let title: String
        let subtitle: String
        let isSelected: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 50)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.white : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
    }
    
    private func loadCashGames() {
        cashGameService.fetchCashGames()
    }
    
    private func startSession() {
        guard let game = selectedGame, let buyInAmount = Double(buyIn), buyInAmount > 0 else { return }
        
        // Start the session
        sessionStore.startLiveSession(
            gameName: game.name,
            stakes: game.stakes,
            buyIn: buyInAmount
        )
        
        // Update UI mode
        sessionMode = .active
    }
    
    // MARK: - Tab Content Views
    
    // Session Tab - Main session view with timer, stack, and quick actions
    private var sessionTabView: some View {
        ScrollView {
            VStack(spacing: 24) {
                timerSection
                    .padding(.horizontal)
                
                chipStackSection
                    .padding(.horizontal)
                
                // Recent Updates Section (Chip / Notes / Hands)
                if !recentUpdates.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)

                        ForEach(recentUpdates.prefix(4)) { item in
                            // Get the share action (will be nil for notes)
                            let shareAction = getShareAction(for: item)
                            
                            SessionUpdateCard(
                                title: item.title,
                                description: item.description,
                                timestamp: item.timestamp,
                                isPosted: false, // Assuming this is for UI state of the card
                                onPost: shareAction // Pass the optional shareAction directly
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 16)
            // No longer need extra bottom padding here, as TabView is padded
            // .padding(.bottom, 70) 
        }
    }
    
    // Helper function to create the appropriate share action for each activity item
    private func getShareAction(for item: UpdateItem) -> (() -> Void)? {
        // No share action for notes
        if item.kind == .note {
            return nil
        }
        
        // Return appropriate action for other types
        return {
            if item.kind == .chip {
                if let update = self.chipUpdates.first(where: { $0.id == item.id }) {
                    let updateContent = "Stack update: $\(Int(update.amount))\(update.note != nil ? "\nNote: \(update.note!)" : "")"
                    self.showShareToFeedDialog(content: updateContent, isHand: false, handData: nil, updateId: update.id)
                }
            } else if item.kind == .hand {
                // Directly find the SavedHand using item.id from handStore
                if let savedHand = self.handStore.savedHands.first(where: { $0.id == item.id }) {
                    // Pass the ParsedHandHistory from the found SavedHand
                    // The content for showShareToFeedDialog can be minimal or derived, as PostEditorView will use the ParsedHandHistory
                    let handContentSummary = self.createSummaryFromParsedHand(hand: savedHand.hand) // Optional: for a brief text part if needed
                    self.showShareToFeedDialog(content: "", isHand: true, handData: savedHand.hand, updateId: savedHand.id)
                } else {
                    print("Error: Could not find SavedHand in handStore for ID: \(item.id)")
                    // Optionally, show an alert to the user that the hand data couldn't be loaded for sharing
                }
            } else if item.kind == .sessionStart {
                // For session start updates, share basic session info
                let sessionInfo = self.getSessionDetailsText()
                self.showShareToFeedDialog(content: "Started a new session", isHand: false)
            }
        }
    }
    
    // Notes Tab - For viewing and adding notes
    private var notesTabView: some View {
        VStack(spacing: 0) {
            // Notes List
            if notes.isEmpty {
                emptyNotesView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(notes.indices, id: \.self) { index in
                            let noteIndex = notes.count - 1 - index
                            let note = notes[noteIndex]
                            NoteCard(
                                text: note,
                                timestamp: Date() // In a real app, would store timestamps with notes
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .sheet(isPresented: $showingSimpleNoteEditor, onDismiss: {
            updateLocalDataFromStore() // Refresh local notes data when editor dismisses
        }) { 
            SimpleNoteEditorView(sessionStore: sessionStore, sessionId: sessionStore.liveSession.id)
        }
    }
    
    private var emptyNotesView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "note.text")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.7))
            
            Text("No Notes")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Text("Add notes to track your thoughts during the session")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    // Hands Tab - For viewing and adding hand histories
    private var handsTabView: some View {
        VStack(spacing: 0) {
            // Filter hands directly in the ForEach to ensure it observes changes to handStore.savedHands
            let currentSessionHands = handStore.savedHands.filter { $0.sessionId == sessionStore.liveSession.id }
                                                              .sorted(by: { $0.timestamp > $1.timestamp })

            if currentSessionHands.isEmpty {
                emptyHandsView // Keep the empty state view
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Use handData.id for ForEach identification, as SavedHand is Identifiable
                        ForEach(currentSessionHands) { handData in 
                            HandDisplayCardView(
                                hand: handData.hand, // Pass the ParsedHandHistory object
                                onReplayTap: { 
                                    // Placeholder for future replay functionality
                                    // You would typically present a HandReplayView here, possibly passing handData.id or handData.hand
                                    print("Replay tapped for hand ID: \(handData.id)")
                                }, 
                                location: "$\(Int(handData.hand.raw.gameInfo.smallBlind))/$\(Int(handData.hand.raw.gameInfo.bigBlind))", // Use stakes as location
                                createdAt: handData.timestamp, // Use handData.timestamp
                                showReplayInFeed: false // Set to false to SHOW the replay button
                            )
                            .padding(.horizontal) // Add some horizontal padding to the card
                        }
                    }
                    .padding(.vertical, 16) // Padding for the content within ScrollView
                }
            }
        }
        .sheet(isPresented: $showingNewHandEntry) {
            NewHandEntryView(sessionId: sessionStore.liveSession.id)
                .environmentObject(handStore)
        }
        .onAppear {
            // Call method on the observed object instance
            self.handStore.loadSavedHands() // Or fetchSavedHands() if that's the correct method name
            self.checkForNewHands() 
        }
    }
    
    private var emptyHandsView: some View {
        VStack(spacing: 16) {
            Spacer()
            
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.7))
            
            Text("No Hand Histories")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Text("Track memorable hands from your session")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    // Posts Tab - For viewing posts related to this session
    private var postsTabView: some View {
        VStack(spacing: 0) {
            if isLoadingSessionPosts && sessionPosts.isEmpty {
                // Loading state
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading posts...")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                        .padding(.top, 16)
                    Spacer()
                }
            } else if sessionPosts.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Spacer()
                    
                    Image(systemName: "text.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.7))
                    
                    Text("No Posts")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("Share updates from this session to see them here")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                }
                .padding()
            } else {
                // Posts list
                ScrollView {
                    LazyVStack(spacing: 0) { // No spacing between posts for Twitter-like feel
                        ForEach(sessionPosts) { post in
                            VStack(spacing: 0) {
                                PostView(
                                    post: post,
                                    onLike: {
                                        Task {
                                            do {
                                                try await postService.toggleLike(postId: post.id ?? "", userId: userId)
                                                // Reload posts after liking
                                
                                                loadSessionPosts()
                                            } catch {
                                                print("Error toggling like: \(error)")
                                            }
                                        }
                                    },
                                    onComment: {
                                        // Show post detail view for commenting
                                        showPostDetail(post)
                                    },
                                    userId: userId
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // Open post detail view when tapping anywhere on the post
                                    showPostDetail(post)
                                }
                                
                                // Divider between posts
                                Rectangle()
                                    .fill(Color.white.opacity(0.06))
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
                .refreshable {
                    await refreshSessionPosts()
                }
            }
        }
        .onAppear {
            // Load posts when tab appears
            loadSessionPosts()
        }
        // Sheet for showing post detail
        .sheet(item: $selectedPost) { post in
            PostDetailView(post: post, userId: userId)
                .environmentObject(postService)
                .environmentObject(userService)
        }
    }
    
    // MARK: - Component Sections
    
    // Timer and controls
    private var timerSection: some View {
        VStack(spacing: 16) {
            // Timer display
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SESSION TIME")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text(String(format: "%02d:%02d:%02d", 
                                formattedElapsedTime.hours,
                                formattedElapsedTime.minutes,
                                formattedElapsedTime.seconds))
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Session stats
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Buy-in: $\(Int(sessionStore.liveSession.buyIn))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    
                    let profit = currentProfit
                    let isProfit = profit >= 0
                    
                    Text(String(format: "%@$%.0f", isProfit ? "+" : "", profit))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(isProfit ? .white : .white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 28/255, green: 30/255, blue: 34/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Controls row
            HStack(spacing: 12) {
                Button(action: { toggleSessionActiveState() }) {
                    HStack(spacing: 8) {
                        Image(systemName: sessionStore.liveSession.isActive ? "pause.fill" : "play.fill")
                        Text(sessionStore.liveSession.isActive ? "Pause" : "Resume")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.3)))
                }

                Button(action: { showingCashoutPrompt = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                        Text("End")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.25)))
                }
            }
        }
    }
    
    // Chip stack graph section
    private var chipStackSection: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Chip Stack")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                if let lastUpdate = chipUpdates.sorted(by: { $0.timestamp > $1.timestamp }).first {
                    Text("Last update: \(formattedTime(lastUpdate.timestamp))")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            
            // Chip Stack Graph
            ChipStackGraph(
                amounts: allChipAmounts,
                startAmount: sessionStore.liveSession.buyIn
            )
            .frame(height: 240)
            .padding(.vertical, 8)
            
            // Buttons row
            HStack(spacing: 12) {
                Button(action: {
                    showingStackUpdateSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 18))
                        Text("Update Stack")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                }
                
                Button(action: {
                    showingRebuySheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 18))
                        Text("Rebuy")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.3))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 28/255, green: 30/255, blue: 34/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Functions
    
    // Toggle session active state (pause/resume)
    private func toggleSessionActiveState() {
        if sessionStore.liveSession.isActive {
            sessionStore.pauseLiveSession()
        } else {
            sessionStore.resumeLiveSession()
        }
    }
    
    // End the session with given cashout amount
    private func endSession(cashout: Double) {
        isLoadingSave = true
        
        Task {
            if self.sessionStore.enhancedLiveSession.chipUpdates.isEmpty || 
               self.sessionStore.enhancedLiveSession.currentChipAmount != cashout {
                self.sessionStore.updateChipStack(amount: cashout, note: "Final cashout amount")
            }
            
            let endedSessionId = await self.sessionStore.endLiveSessionAndGetId(cashout: cashout) 
            
            await MainActor.run {
                self.isLoadingSave = false
                if let sessionId = endedSessionId {
                    if let completedSession = self.sessionStore.getSessionById(sessionId) { 
                        self.completedSessionToShowInSheet = completedSession
                        self.showSessionDetailSheet = true
                        // Do NOT dismiss EnhancedLiveSessionView here; it will be dismissed when the sheet is closed.
                    } else {
                        print("Error: Could not fetch completed session details for ID: \(sessionId)")
                        self.dismiss() // Dismiss if we can't show details
                    }
                } else {
                    print("Error saving session or getting ID.")
                    self.dismiss() 
                }
            }
        }
    }
    
    // Handle stack update from sheet
    private func handleStackUpdate(amount: String, note: String) {
        guard let amountValue = Double(amount) else { return }
        
        // If this is a rebuy (note contains "rebuy" or "add-on")
        if (note.lowercased().contains("rebuy") || note.lowercased().contains("add-on")) && !chipUpdates.isEmpty {
            // Get the current stack amount
            let currentStack = chipUpdates.last?.amount ?? sessionStore.liveSession.buyIn
            
            // Add the rebuy amount to current stack and to buy-in
            let newAmount = currentStack + amountValue
            
            // Update buy-in in store
            sessionStore.updateLiveSessionBuyIn(amount: amountValue)
            
            // Update with the new total stack amount
            sessionStore.updateChipStack(amount: newAmount, note: note)
        } else {
            // Standard stack update with direct amount
            sessionStore.updateChipStack(amount: amountValue, note: note.isEmpty ? nil : note)
        }
        
        // Update local data
        updateLocalDataFromStore()
    }
    
    // Handle hand history input from sheet
    private func handleHandHistoryInput(content: String) {
        // Update the store's enhanced session data
        sessionStore.addHandHistory(content: content)
        
        // Update local data
        updateLocalDataFromStore()
    }
    
    // Share update to feed
    private func showShareToFeedDialog(content: String, isHand: Bool, handData: ParsedHandHistory? = nil, updateId: String? = nil) {
        // First store what's being shared
        // For hand posts, we don't want the text description, just an empty string
        shareToFeedContent = isHand ? "" : content
        shareToFeedIsHand = isHand
        shareToFeedHandData = handData
        shareToFeedUpdateId = updateId
        
        // Now determine the type of content
        let isNote = !isHand && !content.starts(with: "Stack update:") && !content.starts(with: "Session at")
        let isChipUpdate = !isHand && content.starts(with: "Stack update:")
        
        // Store the content type for use in the editor
        shareToFeedIsNote = isNote
        shareToFeedIsChipUpdate = isChipUpdate
        
        // Show the post editor dialog
        if userService.currentUserProfile != nil {
            // Make sure post editor is properly set up
            showingPostEditor = true
        } else {
            // If user profile is not available, prompt user to log in
            showingNoProfileAlert = true
        }
    }
    
    // Update local data from store
    private func updateLocalDataFromStore() {
        chipUpdates = sessionStore.enhancedLiveSession.chipUpdates
        handHistories = sessionStore.enhancedLiveSession.handHistories
        notes = sessionStore.enhancedLiveSession.notes

        // Build recent updates array combining all three types
        var items: [UpdateItem] = []
        
        // Add session start update (always first)
        let sessionStartTime = sessionStore.liveSession.startTime
        items.append(UpdateItem(
            id: "session_start",
            kind: .sessionStart,
            title: "Session Started",
            description: "Game: \(sessionStore.liveSession.gameName) - \(sessionStore.liveSession.stakes) - Buy-in: $\(Int(sessionStore.liveSession.buyIn))",
            timestamp: sessionStartTime
        ))
        
        for chip in chipUpdates {
            items.append(UpdateItem(
                id: chip.id,
                kind: .chip,
                title: "Stack: $\(Int(chip.amount))",
                description: chip.note ?? "Chip stack updated",
                timestamp: chip.timestamp
            ))
        }
        // Notes – since we don't store timestamps natively, approximate with ordering
        for (index, note) in notes.enumerated() {
            let pseudoDate = Date().addingTimeInterval(-Double(index) * 5) // rough ordering
            items.append(UpdateItem(
                id: "note_\(index)",
                kind: .note,
                title: "Note",
                description: note,
                timestamp: pseudoDate
            ))
        }
        for hand in handHistories {
            items.append(UpdateItem(
                id: hand.id,
                kind: .hand,
                title: "Hand Saved",
                description: "Tap to view",
                timestamp: hand.timestamp
            ))
        }
        // sort by time desc
        items.sort { $0.timestamp > $1.timestamp }
        recentUpdates = items
    }
    
    // Format time to readable string
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    // MARK: - Helper Views
    
    // Tab button for custom tab bar
    private func tabButton(title: String, icon: String, tab: LiveSessionTab) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
        }
        .frame(width: 80)
        .contentShape(Rectangle())
        .onTapGesture {
            let wasPostsTab = selectedTab == .posts
            let isPostsTab = tab == .posts
            
            withAnimation {
                selectedTab = tab
            }
            
            // If we're switching to the posts tab, refresh posts
            if !wasPostsTab && isPostsTab {
                loadSessionPosts()
            }
        }
    }
    
    // Chip stack graph
    private struct ChipStackGraph: View {
        let amounts: [Double]
        let startAmount: Double
        
        // Colors for the graph
        private let gradientTop = Color(red: 123/255, green: 255/255, blue: 99/255)
        private let gradientBottom = Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.2)
        
        private var graphColor: Color {
            // Green if profit, red if loss
            if let lastAmount = amounts.last, lastAmount >= startAmount {
                return Color(red: 123/255, green: 255/255, blue: 99/255) // Green
            } else {
                return Color.red
            }
        }
        
        var body: some View {
            if amounts.isEmpty {
                Text("No chip updates yet")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .frame(height: 100)
            } else {
                // Create a simple line graph visualization with gradient fill
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        // Draw gradient fill under the line
                        graphPath(in: geometry)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        graphColor.opacity(0.6),
                                        graphColor.opacity(0.1)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Draw the line path
                        graphPath(in: geometry, closePath: false)
                            .stroke(graphColor, lineWidth: 2)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        
        // Helper function to create the graph path
        private func graphPath(in geometry: GeometryProxy, closePath: Bool = true) -> Path {
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height - 10
                
                let allAmounts = [startAmount] + amounts
                
                // Find min and max values, adding a bit of padding
                let minValue = (allAmounts.min() ?? 0) * 0.95
                let maxValue = max((allAmounts.max() ?? startAmount), startAmount * 1.05)
                let range = maxValue - minValue
                
                // Start point
                let startY = height - height * CGFloat((startAmount - minValue) / range)
                path.move(to: CGPoint(x: 0, y: startY))
                
                // Draw lines through points
                for (index, amount) in amounts.enumerated() {
                    let x = width * CGFloat(index + 1) / CGFloat(amounts.count)
                    let y = height - height * CGFloat((amount - minValue) / range)
                    
                    // Use a smooth curve
                    if index > 0 {
                        let prevX = width * CGFloat(index) / CGFloat(amounts.count)
                        let prevY = height - height * CGFloat((allAmounts[index] - minValue) / range)
                        
                        let controlPoint1 = CGPoint(x: prevX + (x - prevX) / 2, y: prevY)
                        let controlPoint2 = CGPoint(x: prevX + (x - prevX) / 2, y: y)
                        
                        path.addCurve(to: CGPoint(x: x, y: y),
                                     control1: controlPoint1,
                                     control2: controlPoint2)
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                
                // Close the path to create a filled shape
                if closePath {
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
            }
        }
    }
    
    // Helper to convert a parsed hand to a simple text format
    private func createSummaryFromParsedHand(hand: ParsedHandHistory) -> String {
        let gameInfo = hand.raw.gameInfo
        let hero = hand.raw.players.first(where: { $0.isHero }) 
        let heroPnL = hand.raw.pot.heroPnl
        
        var summary = "Game: $\(gameInfo.smallBlind)/$\(gameInfo.bigBlind)\n"
        summary += "Table Size: \(gameInfo.tableSize)\n"
        
        if let heroCards = hero?.cards, heroCards.count >= 2 {
            summary += "Hero Cards: \(heroCards[0]) \(heroCards[1])\n"
        }
        
        // Board cards if available
        var boardCards = ""
        let streets = hand.raw.streets
        if streets.count > 1 && streets[1].name == "flop" {
            boardCards += "Flop: \(streets[1].cards.joined(separator: " "))\n"
        }
        if streets.count > 2 && streets[2].name == "turn" {
            boardCards += "Turn: \(streets[2].cards.joined(separator: " "))\n"
        }
        if streets.count > 3 && streets[3].name == "river" {
            boardCards += "River: \(streets[3].cards.joined(separator: " "))\n"
        }
        
        if !boardCards.isEmpty {
            summary += boardCards
        }
        
        // Result summary
        if let showdown = hand.raw.showdown, showdown {
            summary += "Showdown: "
            if let potDistribution = hand.raw.pot.distribution?.first {
                summary += "\(potDistribution.playerName) wins with \(potDistribution.hand)\n"
            } else {
                summary += "Yes\n"
            }
        }
        
        // PnL
        let pnlText = heroPnL >= 0 ? "+$\(String(format: "%.2f", heroPnL))" : "-$\(String(format: "%.2f", abs(heroPnL)))"
        summary += "Hero PnL: \(pnlText)"
        
        return summary
    }
    
    // Function to check for new hands after wizard is closed
    private func checkForNewHands() {
        print("Checking for new hands for current session...")
        print("Found \(handStore.savedHands.count) total hands")
        print("Session ID: \(sessionStore.liveSession.id)")
        
        // Filter hands for this session and log
        let sessionHands = handStore.savedHands.filter { $0.sessionId == sessionStore.liveSession.id }
        print("Found \(sessionHands.count) hands for this session")
        
        // Process each hand
        for hand in sessionHands {
            // Verify hand is not already tracked in this session
            let isAlreadyTracked = handHistories.contains { entry in
                entry.content.contains("Hand ID: \(hand.id)")
            }
            
            if !isAlreadyTracked {
                print("Adding untracked hand: \(hand.id)")
                
                // Create a content String from the hand to add to the session
                let handSummary = createSummaryFromParsedHand(hand: hand.hand)
                
                // Add ID to identify it
                let contentWithId = "Hand ID: \(hand.id)\n\(handSummary)"
                
                // Add it to the session
                sessionStore.addHandHistory(content: contentWithId)
                updateLocalDataFromStore()
            }
        }
    }
    
    // Helper function to clean up hand history content (remove ID line)
    private func cleanHandHistoryContent(_ content: String) -> String {
        // Remove the "Hand ID:" line if present
        if let range = content.range(of: "Hand ID: "), 
           let endRange = content[range.lowerBound...].range(of: "\n") {
            var cleaned = content
            cleaned.removeSubrange(range.lowerBound..<endRange.upperBound)
            return cleaned
        }
        return content
    }
    
    // Helper function to colorize hand history lines
    private func getColorForHandHistoryLine(_ line: String) -> Color {
        if line.hasPrefix("Hero Cards:") {
            return Color.green.opacity(0.9)
        } else if line.hasPrefix("Hero PnL:") {
            if line.contains("+$") {
                return Color.green
            } else {
                return Color.red.opacity(0.9)
            }
        } else if line.hasPrefix("Flop:") || line.hasPrefix("Turn:") || line.hasPrefix("River:") {
            return Color.blue.opacity(0.8)
        } else if line.hasPrefix("Showdown:") {
            return Color.orange.opacity(0.9)
        } else {
            return Color.white.opacity(0.8)
        }
    }
    
    // Create a new function to minimize session and dismiss view
    func minimizeSession() {
        dismiss()
    }
    
    // Update getSessionDetailsText to include richer info and compute elapsed time
    private func getSessionDetailsText() -> String {
        let gameName = sessionStore.liveSession.gameName
        let stakes = sessionStore.liveSession.stakes
        
        let currentStack = chipUpdates.last?.amount ?? sessionStore.liveSession.buyIn
        let buyIn = sessionStore.liveSession.buyIn
        let profitAmount = currentStack - buyIn
        let profitText = profitAmount >= 0 ? "+$\(Int(profitAmount))" : "-$\(Int(abs(profitAmount)))"
        
        // Elapsed time formatted
        let elapsed = Int(sessionStore.liveSession.elapsedTime)
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let timeText = "\(hours)h \(minutes)m"
        
        // Format exactly as expected by the parser
        return """
        Session at \(gameName) (\(stakes))
        Stack: $\(Int(currentStack)) (\(profitText))
        Time: \(timeText)
        """
    }
    
    // Update the post editor sheet to use the correct components
    private var postEditorSheet: some View {
        // Get session info for badge
        let gameName = sessionStore.liveSession.gameName
        let stakes = sessionStore.liveSession.stakes
        
        // For session result share after session ends
        if let details = sessionDetails {
            // Create session summary content
            let profitText = details.profit >= 0 ? "+$\(Int(details.profit))" : "-$\(Int(abs(details.profit)))"
            let content = """
            Session at \(details.gameName) (\(details.stakes))
            Duration: \(details.duration)
            Buy-in: $\(Int(details.buyIn))
            Cashout: $\(Int(details.cashout))
            Profit: \(profitText)
            """
            
            return PostEditorView(
                userId: userId,
                initialText: content,
                initialHand: nil,
                sessionId: details.sessionId,
                isSessionPost: true,
                isNote: false,
                showFullSessionCard: true,
                sessionGameName: details.gameName,
                sessionStakes: details.stakes
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .environmentObject(handStore)
            .onDisappear {
                // When post editor closes, we need to dismiss the entire view
                dismiss()
            }
        }
        // For notes or hands during the session, show BADGE (not full card)
        else if shareToFeedIsNote || shareToFeedIsHand {
            return PostEditorView(
                userId: userId,
                initialText: shareToFeedContent,
                initialHand: shareToFeedHandData,
                sessionId: sessionStore.liveSession.id,
                isSessionPost: true,
                isNote: shareToFeedIsNote,
                showFullSessionCard: false,  // Just show badge for notes/hands
                sessionGameName: gameName,  // Pass game name directly
                sessionStakes: stakes  // Pass stakes directly
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .environmentObject(handStore)
            .onDisappear {
                handlePostEditorDisappear()
            }
        } 
        // For chip updates, show the FULL session card
        else if shareToFeedIsChipUpdate {
            return PostEditorView(
                userId: userId,
                initialText: getSessionDetailsText() + "\n\n" + shareToFeedContent,
                initialHand: nil,
                sessionId: sessionStore.liveSession.id,
                isSessionPost: true,
                isNote: false,
                showFullSessionCard: true,  // Show full card for chip updates
                sessionGameName: gameName,
                sessionStakes: stakes
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .environmentObject(handStore)
            .onDisappear {
                handlePostEditorDisappear()
            }
        }
        // Default case
        else {
            return PostEditorView(
                userId: userId,
                initialText: getSessionDetailsText() + "\n\n" + shareToFeedContent,
                initialHand: shareToFeedHandData,
                sessionId: sessionStore.liveSession.id,
                isSessionPost: true,
                isNote: false,
                showFullSessionCard: !shareToFeedIsNote && !shareToFeedIsHand,
                sessionGameName: gameName,
                sessionStakes: stakes
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .environmentObject(handStore)
            .onDisappear {
                handlePostEditorDisappear()
            }
        }
    }
    
    // Add a method to handle post editor disappear
    private func handlePostEditorDisappear() {
        // Always refresh posts when returning from post editor
        Task {
            // Small delay to ensure the post has time to be created
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            
            // Refresh session posts
            let posts = await postService.getSessionPosts(sessionId: sessionStore.liveSession.id)
            
            await MainActor.run {
                // Update the session posts
                sessionPosts = posts
                
                // If there was a specific update ID to mark as posted
                if shareToFeedIsHand == false, let updateId = shareToFeedUpdateId {
                    let matchingPosts = posts.filter { $0.content.contains(shareToFeedContent) }
                    
                    if !matchingPosts.isEmpty {
                        // Mark the update as posted since we found a matching post
                        sessionStore.markUpdateAsPosted(id: updateId)
                        updateLocalDataFromStore()
                    }
                }
            }
        }
    }
    
    // Add new sheet for rebuy amount
    private var rebuyView: some View {
        NavigationView {
            ZStack {
                Color(red: 18/255, green: 20/255, blue: 24/255)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("Add Rebuy")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { showingRebuySheet = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Rebuy amount field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REBUY AMOUNT")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        HStack {
                            Text("$")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.gray)
                            
                            TextField("Amount", text: $rebuyAmount)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 25/255, green: 28/255, blue: 32/255))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    
                    // Edit Buy-in Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EDIT TOTAL BUY-IN")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        // Edit Buy-in button/expandable section
                        VStack(spacing: 12) {
                            Button(action: {
                                withAnimation {
                                    showEditBuyIn.toggle()
                                    if showEditBuyIn {
                                        editBuyInAmount = String(sessionStore.liveSession.buyIn)
                                    }
                                }
                            }) {
                                HStack {
                                    Text("Edit Buy-in")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Image(systemName: showEditBuyIn ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 14))
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color(red: 25/255, green: 28/255, blue: 32/255))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            
                            // Expanded edit section
                            if showEditBuyIn {
                                VStack(spacing: 12) {
                                    HStack {
                                        Text("$")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.gray)
                                        
                                        TextField("Total Buy-in Amount", text: $editBuyInAmount)
                                            .keyboardType(.decimalPad)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(red: 25/255, green: 28/255, blue: 32/255).opacity(0.7))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    
                                    Button(action: {
                                        // Update the total buy-in amount
                                        if let amount = Double(editBuyInAmount.trimmingCharacters(in: .whitespacesAndNewlines)), amount > 0 {
                                            sessionStore.setTotalBuyIn(amount: amount)
                                            updateLocalDataFromStore()
                                            withAnimation {
                                                showEditBuyIn = false
                                            }
                                        }
                                    }) {
                                        Text("Update Buy-in")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.black)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.white)
                                            )
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.top, 4)
                                .transition(.opacity)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Submit button
                    Button(action: {
                        handleRebuy()
                        showingRebuySheet = false
                    }) {
                        Text("Add Rebuy")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Color(red: 25/255, green: 28/255, blue: 32/255))
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isValidRebuyAmount() ? Color.white : Color.white.opacity(0.5))
                            )
                    }
                    .disabled(!isValidRebuyAmount())
                }
                .padding(24)
            }
            .navigationBarHidden(true)
        }
    }
    
    // Add helper methods below the other methods
    private func isValidRebuyAmount() -> Bool {
        guard let amount = Double(rebuyAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
              amount > 0 else {
            return false
        }
        return true
    }
    
    private func handleRebuy() {
        guard isValidRebuyAmount() else { return }
        guard let amount = Double(rebuyAmount.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        
        // Update the session store with the new buy-in amount
        sessionStore.updateLiveSessionBuyIn(amount: amount)
        
        // Add a chip update with a rebuy note - fixed method call
        let currentAmount = sessionStore.enhancedLiveSession.currentChipAmount + amount
        sessionStore.updateChipStack(amount: currentAmount, note: "Rebuy: +$\(Int(amount))")
        
        // Update local data
        updateLocalDataFromStore()
        
        // Reset the rebuy amount
        rebuyAmount = ""
    }
    
    // Add a method to mark updates as posted if needed for backward compatibility
    private func markUpdateAsPosted(updateId: String) {
        // Mark the update as posted in the session store
        sessionStore.markUpdateAsPosted(id: updateId)
        
        // Update local data
        updateLocalDataFromStore()
    }
    
    // Function to load posts for the current session
    private func loadSessionPosts() {
        guard !sessionStore.liveSession.id.isEmpty else {
            print("Cannot load posts: Session ID is empty")
            return
        }
        
        isLoadingSessionPosts = true
        print("Loading posts for session ID: \(sessionStore.liveSession.id)")
        
        Task {
            let posts = await postService.getSessionPosts(sessionId: sessionStore.liveSession.id)
            print("Found \(posts.count) posts for this session")
            
            await MainActor.run {
                sessionPosts = posts
                isLoadingSessionPosts = false
            }
        }
    }
    
    // Refresh session posts
    private func refreshSessionPosts() async {
        guard !sessionStore.liveSession.id.isEmpty else {
            print("Cannot refresh posts: Session ID is empty")
            return
        }
        
        isLoadingSessionPosts = true
        print("Refreshing posts for session ID: \(sessionStore.liveSession.id)")
        
        let posts = await postService.getSessionPosts(sessionId: sessionStore.liveSession.id)
        print("Found \(posts.count) posts for this session after refresh")
        
        await MainActor.run {
            sessionPosts = posts
            isLoadingSessionPosts = false
        }
    }
    
    // Add helper method to show post detail
    private func showPostDetail(_ post: Post) {
        selectedPost = post
    }
}

// Define the minimized floating control as a separate view
private struct SessionMinimizedFloatingControl: View {
    let gameName: String
    let statusColor: Color
    let profit: Double
    let onTap: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Button(action: onTap) {
                    HStack {
                        // Session info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gameName)
                                .font(.system(size: 14, weight: .bold))
                            
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 6, height: 6)
                                
                                Text("Session Active")
                                    .font(.system(size: 11))
                            }
                            .opacity(0.8)
                        }
                        
                        Spacer()
                        
                        // Profit indicator
                        Text(String(format: "%+.0f", profit))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(profit >= 0 ? .green : .red)
                        
                        Image(systemName: "chevron.up")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(red: 28/255, green: 30/255, blue: 34/255))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                }
                .foregroundColor(.white)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20) // Increased bottom padding to avoid tab bar overlap
        }
        .zIndex(99) // Ensure it's on top of other UI elements
    }
}

#Preview {
    EnhancedLiveSessionView(
        userId: "preview",
        sessionStore: {
            let store = SessionStore(userId: "preview")
            store.liveSession = LiveSessionData(
                isActive: true,
                startTime: Date(),
                elapsedTime: 7200,
                gameName: "Wynn",
                stakes: "$2/$5/$10",
                buyIn: 1000,
                lastActiveAt: Date()
            )
            return store
        }()
    )
} 

