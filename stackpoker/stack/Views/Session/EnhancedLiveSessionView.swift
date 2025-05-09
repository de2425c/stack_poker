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
    
    // MARK: - Enum Definitions
    enum LiveSessionTab {
        case session
        case notes
        case hands
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
        .fullScreenCover(isPresented: $showingHandWizard) {
            handWizardView
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
        .sheet(isPresented: $showingPostEditor) {
            postEditorSheet
        }
        .sheet(isPresented: $showingRebuySheet) {
            rebuyView
        }
        .alert("Sign In Required", isPresented: $showingNoProfileAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You need to sign in to share content to the feed.")
        }
    }
    
    private var activeSessionView: some View {
        VStack(spacing: 0) {
            // Main content with tabs
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
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            customTabBar
        }
    }
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Session", icon: "timer", tab: .session)
            tabButton(title: "Notes", icon: "note.text", tab: .notes)
            tabButton(title: "Hands", icon: "suit.spade", tab: .hands)
        }
        .padding(.vertical, 12)
        .background(
            Color(red: 22/255, green: 24/255, blue: 28/255)
                .edgesIgnoringSafeArea(.bottom)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.black.opacity(0.3)),
            alignment: .top
        )
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
    
    private var handWizardView: some View {
        NavigationView {
            HandWizardWrapper(
                isPresented: $showingHandWizard,
                sessionId: sessionStore.liveSession.id,
                stakes: sessionStore.liveSession.stakes,
                onDismiss: { checkForNewHands() }
            )
        }
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) { titleView }
        ToolbarItem(placement: .navigationBarLeading) { leadingButton }
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
            if sessionStore.liveSession.isActive {
                sessionMode = .active
            } else if sessionStore.liveSession.lastPausedAt != nil {
                sessionMode = .paused
            }
            // Initialize data from session store's enhanced session
            updateLocalDataFromStore()
            
            // If no chip updates yet, initialize with buy-in
            if chipUpdates.isEmpty {
                handleStackUpdate(amount: String(sessionStore.liveSession.buyIn), note: "Initial buy-in")
            }
            
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
        ScrollView {
            VStack(spacing: 32) {
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
                        // Game selection grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
                            
                            // Add new game card
                            Button(action: { showingAddGame = true }) {
                                VStack(spacing: 12) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    Text("Add Game")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 100)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.15))
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
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 27)
                                    .fill(buyIn.isEmpty ? Color.gray.opacity(0.5) : accentColor)
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
                
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 100)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
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
                            SessionUpdateCard(
                                title: item.title,
                                description: item.description,
                                timestamp: item.timestamp,
                                isPosted: false,
                                onPost: {
                                    // Post content based on type
                                    if item.kind == .chip {
                                        if let update = chipUpdates.first(where: { $0.id == item.id }) {
                                            let updateContent = "Stack update: $\(Int(update.amount))\(update.note != nil ? "\nNote: \(update.note!)" : "")"
                                            showShareToFeedDialog(content: updateContent, isHand: false, handData: nil, updateId: update.id)
                                        }
                                    } else if item.kind == .note {
                                        if let noteId = item.id.split(separator: "_").last,
                                           let index = Int(noteId),
                                           index < notes.count {
                                            let noteContent = notes[index]
                                            showShareToFeedDialog(content: noteContent, isHand: false)
                                        }
                                    } else if item.kind == .hand {
                                        if let entry = handHistories.first(where: { $0.id == item.id }) {
                                            var handData: ParsedHandHistory? = nil
                                            if let hand = handStore.savedHands.first(where: { 
                                                entry.content.contains("Hand ID: \($0.id)") 
                                            }) {
                                                handData = hand.hand
                                            }
                                            showShareToFeedDialog(content: cleanHandHistoryContent(entry.content), isHand: true, handData: handData)
                                        }
                                    } else if item.kind == .sessionStart {
                                        // For session start updates, share basic session info
                                        let sessionInfo = getSessionDetailsText()
                                        showShareToFeedDialog(content: "Started a new session", isHand: false)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 16)
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
            
            // Note input at bottom
            noteInputView
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
    
    private var noteInputView: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            SessionInputField(
                icon: "square.and.pencil",
                placeholdText: "Add a note...",
                text: $noteText,
                onSubmit: {
                    handleSimpleNote()
                }
            )
            .padding(12)
        }
        .background(Color(red: 22/255, green: 24/255, blue: 28/255))
    }
    
    // Hands Tab - For viewing and adding hand histories
    private var handsTabView: some View {
        VStack(spacing: 0) {
            // Hand Histories List
            if handHistories.isEmpty {
                emptyHandsView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(handHistories.sorted(by: { $0.timestamp > $1.timestamp }), id: \.id) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Hand History")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    Text(formattedTime(entry.timestamp))
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                                
                                // Cleaner display of hand history with proper formatting
                                VStack(alignment: .leading, spacing: 4) {
                                    let content = cleanHandHistoryContent(entry.content)
                                    let lines = content.split(separator: "\n")
                                    
                                    ForEach(0..<lines.count, id: \.self) { index in
                                        Text(String(lines[index]))
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(getColorForHandHistoryLine(String(lines[index])))
                                    }
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(red: 25/255, green: 28/255, blue: 32/255))
                                )
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }
                    .padding(16)
                }
            }
            
            // Add hand button at bottom
            VStack(spacing: 0) {
                Divider()
                    .background(Color.white.opacity(0.1))
                
                Button(action: {
                    showingHandWizard = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        
                        Text("Add Hand History")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }
            .background(Color(red: 22/255, green: 24/255, blue: 28/255))
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
            // Make one final stack update to record the cashout amount
            if sessionStore.enhancedLiveSession.chipUpdates.isEmpty || 
               sessionStore.enhancedLiveSession.currentChipAmount != cashout {
                sessionStore.updateChipStack(amount: cashout, note: "Final cashout amount")
            }
            
            if let error = await sessionStore.endLiveSessionAsync(cashout: cashout) {
                await MainActor.run {
                    isLoadingSave = false
                    print("Error saving session: \(error.localizedDescription)")
                    // Could show an alert here
                }
            } else {
                await MainActor.run {
                    isLoadingSave = false
                    dismiss()
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
    
    // Handle simple note input
    private func handleSimpleNote() {
        guard !noteText.isEmpty else { return }
        
        // Update the store's enhanced session data
        sessionStore.addNote(note: noteText)
        
        // Update local data
        updateLocalDataFromStore()
        
        // Clear the input text
        noteText = ""
        
        // Ensure new hands are checked (in case any were added)
        checkForNewHands()
    }
    
    // Share update to feed
    private func showShareToFeedDialog(content: String, isHand: Bool, handData: ParsedHandHistory? = nil, updateId: String? = nil) {
        // First store what's being shared
        shareToFeedContent = content
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
            withAnimation {
                selectedTab = tab
            }
        }
    }
    
    // App background
    private struct AppBackgroundView: View {
        var body: some View {
            Color(red: 20/255, green: 22/255, blue: 26/255)
                .ignoresSafeArea()
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
        // For notes or hands, show full session card
        if shareToFeedIsNote || shareToFeedIsHand {
            return PostEditorView(
                userId: userId,
                initialText: shareToFeedContent,
                hand: shareToFeedHandData,
                sessionId: sessionStore.liveSession.id,
                isSessionPost: true,
                isNote: shareToFeedIsNote,
                showFullSessionCard: true  // Use full card for notes/hands
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .onDisappear {
                handlePostEditorDisappear()
            }
        } 
        // For chip updates, show the compact badge
        else if shareToFeedIsChipUpdate {
            return PostEditorView(
                userId: userId,
                initialText: getSessionDetailsText() + "\n\n" + shareToFeedContent,
                hand: nil,
                sessionId: sessionStore.liveSession.id,
                isSessionPost: true,
                isNote: false,
                showFullSessionCard: false  // Use badge for chip updates
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .onDisappear {
                handlePostEditorDisappear()
            }
        }
        // Default case
        else {
            return PostEditorView(
                userId: userId,
                initialText: getSessionDetailsText() + "\n\n" + shareToFeedContent,
                hand: shareToFeedHandData,
                sessionId: sessionStore.liveSession.id,
                isSessionPost: true,
                isNote: false,
                showFullSessionCard: shareToFeedIsNote || shareToFeedIsHand  // Based on content type
            )
            .environmentObject(postService)
            .environmentObject(userService)
            .onDisappear {
                handlePostEditorDisappear()
            }
        }
    }
    
    // Add a method to handle post editor disappear
    private func handlePostEditorDisappear() {
        if shareToFeedIsHand == false, let updateId = shareToFeedUpdateId {
            Task {
                // Small delay to ensure the post has time to be created
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Check if the post exists in the feed with this session id
                let posts = await postService.getSessionPosts(sessionId: sessionStore.liveSession.id)
                let matchingPosts = posts.filter { $0.content.contains(shareToFeedContent) }
                
                if !matchingPosts.isEmpty {
                    // Mark the update as posted since we found a matching post
                    sessionStore.markUpdateAsPosted(id: updateId)
                    await MainActor.run {
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
                Color(red: 17/255, green: 18/255, blue: 23/255)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Text("Add Rebuy")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rebuy Amount")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                        
                        TextField("0", text: $rebuyAmount)
                            .keyboardType(.decimalPad)
                            .padding()
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(10)
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        handleRebuy()
                        showingRebuySheet = false
                    }) {
                        Text("Add Rebuy")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                isValidRebuyAmount() 
                                ? Color(red: 123/255, green: 255/255, blue: 99/255)
                                : Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.5)
                            )
                            .cornerRadius(12)
                    }
                    .disabled(!isValidRebuyAmount())
                }
                .padding()
            }
            .navigationBarItems(trailing: Button("Cancel") {
                showingRebuySheet = false
            })
            .navigationBarTitleDisplayMode(.inline)
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

// Hand wizard wrapper to make it easier to dismiss and handle session context
struct HandWizardWrapper: View {
    @Binding var isPresented: Bool
    let sessionId: String
    let stakes: String
    let onDismiss: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack {
            // The actual hand entry wizard
            ManualHandEntryWizardView(
                sessionId: sessionId,
                stakes: stakes,
                onComplete: {
                    isPresented = false
                    onDismiss()
                }
            )
            .ignoresSafeArea()
            
            // Custom navigation for easier dismissal
            VStack {
                HStack {
                    Button(action: {
                        isPresented = false
                        onDismiss()
                    }) {
                        HStack {
                            Image(systemName: "chevron.left")
                            Text("Back to Session")
                        }
                        .foregroundColor(.white)
                        .padding(8)
                        .padding(.horizontal, 8)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(20)
                    }
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
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
