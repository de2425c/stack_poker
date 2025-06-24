import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import PhotosUI

struct EnhancedLiveSessionView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var postService = PostService()
    @StateObject private var userService = UserService()
    let userId: String
    @ObservedObject var sessionStore: SessionStore
    var preselectedEvent: Event? = nil // Optional preselected event
    @StateObject private var cashGameService = CashGameService(userId: Auth.auth().currentUser?.uid ?? "")
    @StateObject private var stakeService = StakeService() // Add StakeService
    @StateObject private var manualStakerService = ManualStakerService() // Add ManualStakerService
    @StateObject private var challengeService = ChallengeService(userId: Auth.auth().currentUser?.uid ?? "") // Add ChallengeService
    @StateObject private var eventStakingService = EventStakingService() // Add EventStakingService
    @StateObject private var sessionNotificationService = SessionNotificationService() // Add SessionNotificationService
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
    @State private var gameToDelete: CashGame? = nil // For delete confirmation
    @State private var showingDeleteGameAlert = false // For delete confirmation
    
    // Staking State Variables - COPIED FROM SessionFormView
    @State private var stakerConfigs: [StakerConfig] = [] // Array for multiple stakers
    @State private var stakerConfigsForPopup: [StakerConfig] = [] // Temporary copy for the popup
    @State private var showStakingSection = false // To toggle visibility of staking fields
    @State private var showingStakingPopup = false // New state for floating popup
    
    // Existing stakes state variables
    @State private var existingStakes: [Stake] = [] // Stakes for this session
    @State private var isLoadingStakes = false // Loading state for stakes
    
    // Data model values - initialized onAppear
    @State private var chipUpdates: [ChipStackUpdate] = []
    @State private var notes: [String] = []
    @State private var sessionPosts: [Post] = []
    @State private var isLoadingSessionPosts = false
    
    // Recent updates feed (chip updates, notes, hands)
    @State private var recentUpdates: [UpdateItem] = []
    
    // Single lightweight struct for feed display
    private struct UpdateItem: Identifiable {
        enum Kind { case chip, note, sessionStart } // REMOVED: hand
        let id: String
        let kind: Kind
        let title: String
        let description: String
        let timestamp: Date
    }
    
    // New states
    // REMOVED: @State private var showingHandWizard = false
    
    // Add a state variable for minimizing the entire session
    @State private var sessionMinimized = false
    
    // New states for share to feed
    @State private var showingNoProfileAlert = false
    
    // Add new state for edit session sheet
    @State private var showingEditSessionSheet = false
    
    // Add states for editing session details
    @State private var editSessionStartTime = Date()
    @State private var editGameName = ""
    @State private var editStakes = ""
    
    // Add state for discard session confirmation
    @State private var showingDiscardSessionAlert = false
    
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
    @State private var shareToFeedIsSessionStart = false // New state for session start sharing
    
    // State variables for new sharing options
    @State private var showingShareHandSelector = false
    @State private var showingShareNoteSelector = false
    @State private var showingShareChipUpdateSelector = false
    
    // State variables for multi-day session progression
    @State private var showingNextDayConfirmation = false
    @State private var nextDayDate = Date()
    
    // Add state for tracking selected post
    @State private var selectedPost: Post? = nil
    
    // Add state variable for tracking whether the edit buy-in section is expanded
    @State private var showEditBuyIn = false
    @State private var editBuyInAmount = ""
    @State private var showingEditBuyInSheet = false
    
    // New states
    @State private var showingShareToFeedPrompt = false
    @State private var sessionDetails: (buyIn: Double, cashout: Double, profit: Double, duration: String, gameName: String, stakes: String, sessionId: String)? = nil
    @State private var showingSimpleNoteEditor = false // New state for presenting the note editor
    @State private var completedSessionToShowInSheet: Session? = nil // For sheet presentation
    @State private var showSessionDetailSheet = false // Controls sheet presentation
    
    // States for editing notes
    @State private var noteToEdit: String? = nil
    @State private var noteToEditId: String? = nil // Assuming notes will have IDs for reliable editing
    @State private var showingEditNoteSheet = false
    
    // Group sharing state for notes
    @State private var showingGroupSelection = false
    @State private var noteToShare: String?
    @State private var showingShareSuccess = false
    @State private var shareSuccessMessage = ""
    
    // Simple display array for notes - completely separate from complex session store
    @State private var displayNotes: [String] = []
    
    // State for Post Tab sharing options
    @State private var showingPostShareOptions = false
    @State private var showingLiveSessionPostEditor = false
    

    
    // Consolidated sharing flow state
    enum SharingFlowState {
        case none
        case resultShare
        case imagePicker
        case imageComposition
        case postEditor
    }
    @State private var sharingFlowState: SharingFlowState = .none
    @State private var selectedImageForResult: UIImage? = nil
    @State private var selectedPhotoForResult: PhotosPickerItem? = nil
    
    // MARK: - Enum Definitions
    enum LiveSessionTab {
        case session
        case notes
        case posts
    }
    
    enum SessionMode {
        case setup    // Initial game selection and buy-in
        case active   // Session is running
        case paused   // Session is paused
        case ending   // Session is ending, entering cashout
    }
    
    // MARK: - Tournament Support
    @State private var selectedLogType: SessionLogType = .cashGame // Choose between CASH GAME or TOURNAMENT
    // Tournament setup fields
    @State private var tournamentName: String = ""
    @State private var showingEventSelector = false
    @State private var tournamentCasino: String = ""
    @State private var baseBuyInTournament: String = ""
    @State private var selectedTournamentGameType: TournamentGameType = .nlh
    @State private var selectedTournamentFormat: TournamentFormat = .standard
    // Runtime helpers for tournament sessions
    @State private var isTournamentSession: Bool = false
    @State private var baseBuyInForTournament: Double = 0
    @State private var tournamentRebuyCount: Int = 0
    
    // MARK: - Computed Properties
    
    private var sessionTitle: String {
        if sessionMode == .setup {
            return "New Session"
        } else {
            let dayText = sessionStore.liveSession.currentDay > 1 ? "Day \(sessionStore.liveSession.currentDay) • " : ""
            
            if isTournamentSession {
                let buyInText = baseBuyInTournament.isEmpty ? "" : " ($\(baseBuyInTournament) Buy-in)" // Updated to use baseBuyInTournament directly
                return "\(dayText)\(sessionStore.liveSession.tournamentName ?? tournamentName)\(buyInText)" // Use local tournamentName if store is nil
            } else {
                return "\(dayText)\(sessionStore.liveSession.stakes) @ \(sessionStore.liveSession.gameName)"
            }
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
    
    // Computed property to get valid staker configs
    private var validStakerConfigs: [StakerConfig] {
        let filtered = stakerConfigs.filter { config in
            // Check if percentage and markup are filled (this is the essential data)
            let hasValidData = !config.percentageSold.isEmpty && !config.markup.isEmpty
            
            // Check if the config has valid staker selection
            let hasValidStaker: Bool
            if config.isManualEntry {
                hasValidStaker = config.selectedManualStaker != nil || !config.manualStakerName.isEmpty
            } else {
                // For app users, check if we have a selectedStaker OR if we can restore from originalStakeUserId
                if config.selectedStaker != nil {
                    hasValidStaker = true
                } else if let originalUserId = config.originalStakeUserId,
                          let existingProfile = userService.loadedUsers[originalUserId] {
                    // Try to restore the staker profile if it's available
                    print("[EnhancedLiveSessionView] Auto-restoring staker profile for validation: \(existingProfile.username)")
                    // Note: We can't modify the config here in the computed property, but we know it's restorable
                    hasValidStaker = true
                } else {
                    hasValidStaker = false
                }
            }
            
            let isValid = hasValidStaker && hasValidData
            
            if !isValid {
                print("[EnhancedLiveSessionView] Invalid staker config: hasValidStaker=\(hasValidStaker), hasValidData=\(hasValidData), isManual=\(config.isManualEntry), percentage='\(config.percentageSold)', markup='\(config.markup)', selectedStaker=\(config.selectedStaker?.username ?? "nil"), originalUserId=\(config.originalStakeUserId ?? "nil")")
            }
            
            return isValid
        }
        
        print("[EnhancedLiveSessionView] validStakerConfigs: \(filtered.count) out of \(stakerConfigs.count) total configs")
        return filtered
    }
    
    // MARK: - Main Body
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
            mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // Remove the keyboard from pushing the whole view up - REMOVED ignoresSafeArea(.keyboard)
            // .ignoresSafeArea(.keyboard, edges: .all)
            // Navigation modifiers moved to mainContent to avoid duplication
        }
        // Navigation modifiers moved to mainContent to avoid duplication
        .overlay(
            // Add floating staking popup overlay
            FloatingStakingPopup(
                isPresented: $showingStakingPopup,
                stakerConfigs: $stakerConfigsForPopup, // Pass the copy here
                userService: userService,
                manualStakerService: manualStakerService,
                userId: userId,
                primaryTextColor: .white,
                secondaryTextColor: Color.white.opacity(0.7),
                glassOpacity: 0.01,
                materialOpacity: 0.2
            )
        )
        .onChange(of: showingStakingPopup) { newValue in
            if !newValue {
                // When popup is dismissed, sync the main stakerConfigs from the popup's copy
                print("[EnhancedLiveSessionView] Popup dismissed. Syncing stakerConfigs.")
                print("[EnhancedLiveSessionView] Before sync, main stakerConfigs count: \(stakerConfigs.count)")
                print("[EnhancedLiveSessionView] Popup copy stakerConfigsForPopup count: \(stakerConfigsForPopup.count)")
                
                // Enhanced sync: preserve existing user profiles if they're missing in popup copy
                for (index, popupConfig) in stakerConfigsForPopup.enumerated() {
                    // If the popup config lost the selected staker but we have an originalStakeUserId,
                    // try to restore it from the userService
                    if popupConfig.selectedStaker == nil && !popupConfig.isManualEntry {
                        if let originalUserId = popupConfig.originalStakeUserId,
                           let existingProfile = userService.loadedUsers[originalUserId] {
                            print("[EnhancedLiveSessionView] Restoring missing staker profile for \(existingProfile.username)")
                            stakerConfigsForPopup[index].selectedStaker = existingProfile
                        }
                    }
                }
                
                // It's crucial that stakerConfigs is updated to reflect changes made in the popup.
                // This will include any additions or removals.
                self.stakerConfigs = self.stakerConfigsForPopup
                print("[EnhancedLiveSessionView] After sync, main stakerConfigs count: \(stakerConfigs.count)")
                

                
                // Verify that we still have valid configs after sync
                let validCount = validStakerConfigs.count
                print("[EnhancedLiveSessionView] After sync, valid configs: \(validCount)")
                
                // After syncing, you might need to save these stakes if the session is active
                // or if they are meant to be persisted immediately without ending the session.
                // For now, this just updates the @State, persistence happens on session end.
            }
        }
        .onChange(of: stakerConfigs) { newValue in
            // Persist current staking configs locally keyed by the liveSession UUID so they survive pause-resume even if Firestore write fails.
            guard !sessionStore.liveSession.id.isEmpty else { return }
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "StakerConfigs_\(sessionStore.liveSession.id)")
            }
        }
        .sheet(isPresented: $showSessionDetailSheet) {
            if let session = completedSessionToShowInSheet {
                NavigationView {
                    SessionDetailView(session: session)
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                Button("Done") {
                                    showSessionDetailSheet = false
                                    self.dismiss() 
                                }
                                .foregroundColor(.white)
                            }
                        }
                }
                .environmentObject(self.sessionStore) // Ensure SessionStore is injected
                .environmentObject(self.userService) // Add UserService for staking details
            }
        }
        .sheet(isPresented: $showingEditSessionSheet) {
            editSessionSheet
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
        // Prevent the keyboard from pushing the whole view up
        // .ignoresSafeArea(.keyboard, edges: .all)
        // Restore the original view modifiers that were accidentally removed
        .navigationTitle(sessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .accentColor(.white)
        .onAppear(perform: handleOnAppear)
        // Sheets and alerts
        .sheet(isPresented: $showingStackUpdateSheet) { stackUpdateSheet }
        .sheet(isPresented: $showingHandHistorySheet) { handHistorySheet }
        .sheet(isPresented: $showingRebuySheet) { rebuyView }
        .sheet(isPresented: $showingEditBuyInSheet) { editBuyInView }
        .fullScreenCover(isPresented: .constant(sharingFlowState != .none)) {
            Group {
                switch sharingFlowState {
                case .none:
                    EmptyView()
                case .resultShare:
                    sessionResultShareView
                case .imagePicker:
                    PhotosPicker(selection: $selectedPhotoForResult, matching: .images) {
                        VStack {
                            Text("Select Photo")
                                .font(.title)
                                .foregroundColor(.white)
                                .padding()
                            Button("Cancel") {
                                sharingFlowState = .resultShare
                            }
                            .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppBackgroundView())
                    }
                    .onChange(of: selectedPhotoForResult) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                selectedImageForResult = uiImage
                                sharingFlowState = .imageComposition
                            }
                        }
                    }
                case .imageComposition:
                    if let details = sessionDetails, let backgroundImage = selectedImageForResult {
                        let sessionData: [String: Any] = [
                            "id": details.sessionId,
                            "userId": userId,
                            "gameName": details.gameName,
                            "stakes": details.stakes,
                            "buyIn": details.buyIn,
                            "cashout": details.cashout,
                            "profit": details.profit,
                            "startDate": Timestamp(date: sessionStore.liveSession.startTime),
                            "endTime": Timestamp(date: Date()),
                            "hoursPlayed": sessionStore.liveSession.elapsedTime / 3600
                        ]
                        let session = Session(id: details.sessionId, data: sessionData)
                        
                        if #available(iOS 16.0, *) {
                            ImageCompositionView(session: session, backgroundImage: backgroundImage) {
                                // Called when X button is tapped - go back to result share
                                sharingFlowState = .resultShare
                            }
                        } else {
                            Text("Image composition requires iOS 16.0+")
                                .onAppear {
                                    selectedImageForResult = nil
                                    sharingFlowState = .none
                                }
                        }
                    }
                case .postEditor:
                    // Show post editor within the sharing flow
                    if let details = sessionDetails {
                        let sessionData: [String: Any] = [
                            "id": details.sessionId,
                            "userId": userId,
                            "gameName": details.gameName,
                            "stakes": details.stakes,
                            "buyIn": details.buyIn,
                            "cashout": details.cashout,
                            "profit": details.profit,
                            "startDate": Timestamp(date: sessionStore.liveSession.startTime),
                            "endTime": Timestamp(date: Date()),
                            "hoursPlayed": sessionStore.liveSession.elapsedTime / 3600
                        ]
                        let completedSession = Session(id: details.sessionId, data: sessionData)
                        
                        SessionPostEditorWrapper(
                            userId: userId,
                            completedSession: completedSession,
                            onSuccess: {
                                sharingFlowState = .resultShare
                            },
                            onCancel: {
                                sharingFlowState = .resultShare
                            }
                        )
                        .environmentObject(postService)
                        .environmentObject(userService)
                        .environmentObject(sessionStore)
                    }
                }
            }
        }
        .alert("Exit Session?", isPresented: $showingExitAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Exit Without Saving", role: .destructive) { dismiss() }
            Button("End & Cashout") { 
                cashoutAmount = String(Int(sessionStore.enhancedLiveSession.currentChipAmount))
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
            Button("Not Now", role: .cancel) { dismiss() }
            Button("Share to Feed") {
                if let details = sessionDetails, userService.currentUserProfile != nil {
                    sharingFlowState = .postEditor
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

        .alert("Sign In Required", isPresented: $showingNoProfileAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("You need to sign in to share content to the feed.")
        }
        .alert("Note Shared", isPresented: $showingShareSuccess) {
            Button("OK") { }
        } message: {
            Text(shareSuccessMessage)
        }
        .sheet(isPresented: $showingNextDayConfirmation) {
            nextDayConfirmationSheet
        }
    }
    
    private var activeSessionView: some View {
        activeSessionContent // Call the new extracted view
                    .sheet(isPresented: $showingPostShareOptions) { postShareOptionsSheet }
        // REMOVED: .sheet(isPresented: $showingShareHandSelector) { shareHandSelectorSheet }
        .sheet(isPresented: $showingShareNoteSelector) { shareNoteSelectorSheet }
        .sheet(isPresented: $showingShareChipUpdateSelector) { shareChipUpdateSelectorSheet }
        .sheet(isPresented: $showingLiveSessionPostEditor, onDismiss: {
            handlePostEditorDisappear()
        }) { liveSessionPostEditorSheet }
    }
    
    // New extracted view for the core content of activeSessionView
    private var activeSessionContent: some View {
        ZStack(alignment: .bottom) { // Align content to the bottom for the tab bar
            // TabView takes up the main space
            TabView(selection: $selectedTab) {
                sessionTabView
                    .tag(LiveSessionTab.session)
                    .contentShape(Rectangle())
                
                notesTabView
                    .tag(LiveSessionTab.notes)
                    .contentShape(Rectangle())
                
                postsTabView
                    .tag(LiveSessionTab.posts)
                    .contentShape(Rectangle())
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity) // Ensure TabView uses full available space
            // Add bottom padding to the TabView itself to make space for the floating tab bar
            // Reduced padding to properly accommodate the tab bar height
            .padding(.bottom, 70) // Reduced from 80 to account for tab bar height
            
            // Container for the floating tab bar
            customTabBar
                .padding(.horizontal, 20) // Padding from screen edges
                .padding(.bottom, 0) // Fixed: Much reduced padding to position tab bar near bottom, accounting for safe area
        }
        // REMOVE these sheets from here as they are now on activeSessionView
        // .sheet(isPresented: $showingPostShareOptions) { postShareOptionsSheet }
        // .sheet(isPresented: $showingShareHandSelector) { shareHandSelectorSheet }
        // .sheet(isPresented: $showingShareNoteSelector) { shareNoteSelectorSheet }
        // .sheet(isPresented: $showingShareChipUpdateSelector) { shareChipUpdateSelectorSheet }
    }
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "Session", icon: "timer", tab: .session)
            tabButton(title: "Notes", icon: "note.text", tab: .notes)
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
        // Enhanced StackUpdateSheet with glassy style
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                    .onTapGesture {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Update Stack")
                            .font(.plusJakarta(.title3, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { showingStackUpdateSheet = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Current Chips Field using GlassyInputField
                    VStack(alignment: .leading, spacing: 16) {
                        GlassyInputField(
                            icon: "dollarsign.circle",
                            title: "Current Chips",
                            content: AnyGlassyContent(TextFieldContent(
                                text: $chipAmount,
                                keyboardType: .decimalPad,
                                prefix: "$",
                                textColor: .white,
                                prefixColor: .gray
                            )),
                            glassOpacity: 0.01,
                            labelColor: .gray,
                            materialOpacity: 0.2
                        )
                        
                        // Optional Note Field
                        GlassyInputField(
                            icon: "note.text",
                            title: "Note (Optional)",
                            content: AnyGlassyContent(TextFieldContent(
                                text: $noteText,
                                keyboardType: .default,
                                textColor: .white
                            )),
                            glassOpacity: 0.01,
                            labelColor: .gray,
                            materialOpacity: 0.2
                        )
                    }
                    
                    Spacer()
                    
                    // Save Button
                    Button(action: {
                        handleStackUpdate(amount: chipAmount, note: noteText)
                        showingStackUpdateSheet = false
                        chipAmount = ""
                        noteText = ""
                    }) {
                        Text("Update Stack")
                            .font(.plusJakarta(.body, weight: .bold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(chipAmount.isEmpty ? Color.white.opacity(0.5) : Color.white)
                            )
                    }
                    .disabled(chipAmount.isEmpty)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: geometry.size.height, alignment: .top)
            }
            .onTapGesture {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    
    private var handHistorySheet: some View {
        HandHistoryInputSheet(
            isPresented: $showingHandHistorySheet,
            handText: $handHistoryText,
            onSubmit: handleHandHistoryInput
        )
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) { titleView }
        ToolbarItem(placement: .navigationBarLeading) { leadingButton }
        ToolbarItem(placement: .navigationBarTrailing) { trailingToolbarButton }
    }
    
    // Extracted trailing button to reduce complexity
    @ViewBuilder
    private var trailingToolbarButton: some View {
        if sessionMode == .setup {
            // No trailing button during setup
            EmptyView()
        } else if selectedTab == .notes {
            plusButton(action: { showingSimpleNoteEditor = true })
        } else if selectedTab == .posts {
            plusButton(action: { showingPostShareOptions = true })
        } else if selectedTab == .session {
            // Edit button for session tab
            Button(action: { 
                // Initialize edit values with current session data
                editSessionStartTime = sessionStore.liveSession.startTime
                editGameName = sessionStore.liveSession.gameName
                editStakes = sessionStore.liveSession.stakes
                showingEditSessionSheet = true 
            }) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(accentColor)
            }
        }
    }
    
    private func plusButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(accentColor)
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
        print("🔥🔥🔥 [EnhancedLiveSessionView] handleOnAppear called")
        print("🔥🔥🔥 Session buyIn: \(sessionStore.liveSession.buyIn)")
        print("🔥🔥🔥 Session ID: \(sessionStore.liveSession.id)")
        print("🔥🔥🔥 Session currentDay: \(sessionStore.liveSession.currentDay)")
        print("🔥🔥🔥 Session pausedForNextDay: \(sessionStore.liveSession.pausedForNextDay)")
        
        // Check if there's an active session first
        if sessionStore.liveSession.buyIn > 0 { // buyIn > 0 means a session (cash or tourney) exists
            print("🔥🔥🔥 [EnhancedLiveSessionView] FOUND ACTIVE SESSION")
            
            // DETECT ERROR STATE: Check for "Final cashout amount" entries which indicate a completed session
            let hasFinalCashoutEntry = sessionStore.enhancedLiveSession.chipUpdates.contains { update in
                update.note?.contains("Final cashout amount") == true
            }
            
            if hasFinalCashoutEntry {
                // This is an error state - a completed session is still active
                print("[EnhancedLiveSessionView] ERROR: Detected 'Final cashout amount' entry in active session. Clearing session state.")
                sessionStore.endAndClearLiveSession()
                sessionMode = .setup
                loadCashGames()
                return
            }
            
            // Determine session mode more directly
            sessionMode = sessionStore.liveSession.isActive ? .active : .paused
            
            // NEW: Restore tournament state if it is a tournament session
            isTournamentSession = sessionStore.liveSession.isTournament
            if isTournamentSession {
                tournamentName = sessionStore.liveSession.tournamentName ?? "Tournament"
                baseBuyInForTournament = sessionStore.liveSession.baseTournamentBuyIn ?? 0
                // Ensure the buyIn field in the view (if used for display in tournament active view) reflects total
                // For tournaments, liveSession.buyIn in SessionStore tracks the *total* buy-in including rebuys.
                // If baseBuyInTournament string is needed for UI and not set, set it from baseBuyInForTournament double
                if self.baseBuyInTournament.isEmpty && baseBuyInForTournament > 0 {
                    self.baseBuyInTournament = String(format: "%.0f", baseBuyInForTournament)
                }
            } else {
                // If it's a new cash session or the initial buy-in hasn't been recorded as a chip update yet
                if sessionStore.enhancedLiveSession.chipUpdates.isEmpty && sessionStore.liveSession.buyIn > 0 {
                     sessionStore.updateChipStack(amount: sessionStore.liveSession.buyIn, note: "Initial buy-in")
                }
            }
            // Initialize data from session store's enhanced session
            updateLocalDataFromStore() // This will now include Session Started and the initial chip update if just added
            
            // Load existing stakes for this session
            loadExistingStakes()
            
            loadSessionPosts()
            
            // REMOVED: Hand checking functionality for launch
            // Task {
            //     // Hand functionality removed
            // }
        } else {
            // No active session, show setup
            sessionMode = .setup
            loadCashGames()
        }
        
        // Log the state for debugging



        
        // Handle preselected event if provided
        if let event = preselectedEvent {
            selectedLogType = .tournament
            tournamentName = event.event_name
            
            if let usdBuyin = event.buyin_usd {
                baseBuyInTournament = String(format: "%.0f", usdBuyin)
            } else if let parsedBuyin = parseBuyinToDouble(event.buyin_string) {
                baseBuyInTournament = String(format: "%.0f", parsedBuyin)
            } else {
                baseBuyInTournament = ""
            }
            
            tournamentCasino = event.casino ?? ""
            
            // Automatically populate staker configuration from accepted event staking invites
            Task {
                await loadEventStakingInvites(for: event)
            }
        }
        
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
                .onTapGesture {
                    // Dismiss keyboard when tapping background
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                
            ScrollView {
                VStack(spacing: 20) { // This is the main content VStack for the ScrollView
                    // Add top padding for transparent navigation bar - REDUCED
                    Spacer()
                        .frame(height: 10) // Reduced from 64
                    
                    // Session type selector
                    Picker("Session Type", selection: $selectedLogType) {
                        ForEach(SessionLogType.allCases) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Game Selection Section (Cash Games)
                    if selectedLogType == .cashGame {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Select Game")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                                
                                Spacer()
                                
                                // Clean + button for adding games
                                Button(action: { showingAddGame = true }) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            Circle()
                                                .fill(Color.gray.opacity(0.3))
                                        )
                                }
                                .padding(.trailing, 6)
                            }
                            .padding(.bottom, 2)
                            
                            if cashGameService.cashGames.isEmpty {
                                VStack {
                                    Text("No games added. Use the + button above to add a new game.")
                                        .font(.plusJakarta(.caption, weight: .medium))
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.vertical, 20)
                                .frame(maxWidth: .infinity)
                            } else {
                                // Game selection horizontal scroll
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                    ForEach(cashGameService.cashGames) { game in
                                            let stakes = formatStakes(game: game)
                                        GameCard(
                                                stakes: stakes,
                                                name: game.name,
                                                gameType: game.gameType,
                                                isSelected: selectedGame?.id == game.id,
                                                titleColor: .white,
                                                subtitleColor: Color.white.opacity(0.7),
                                                glassOpacity: 0.01,
                                                materialOpacity: 0.2
                                        )
                                        .onTapGesture {
                                            selectedGame = game
                                        }
                                        .contextMenu { // Added context menu for deletion
                                            Button(role: .destructive) {
                                                gameToDelete = game
                                                showingDeleteGameAlert = true
                                            } label: {
                                                Label("Delete Game", systemImage: "trash")
                                            }
                                        }
                                    }
                                    
                                        // Add Game Button with glassy style
                                        AddGameButton(
                                            textColor: .white,
                                            glassOpacity: 0.01,
                                            materialOpacity: 0.2
                                        )
                                        .onTapGesture {
                                            showingAddGame = true
                                        }
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(.horizontal)
                        
                        // Buy-in Section
                        if selectedGame != nil {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Buy-in Amount")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                                    .padding(.bottom, 2)
                                
                                // Glassy Buy-in field
                                GlassyInputField(
                                    icon: "dollarsign.circle",
                                    title: "Buy in",
                                    content: AnyGlassyContent(TextFieldContent(text: $buyIn, keyboardType: .decimalPad, prefix: "$", textColor: .white, prefixColor: .gray)),
                                    glassOpacity: 0.01,
                                    labelColor: .gray,
                                    materialOpacity: 0.2
                                )
                            }
                            .padding(.horizontal)
                        }
                    } // End of Cash Game Section
                    
                    // Tournament Setup Section
                    if selectedLogType == .tournament {
                        VStack(alignment: .leading, spacing: 12) { // This is the VStack for tournament content
                            HStack {
                                Text("Tournament Details")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: { showingEventSelector = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar.badge.plus")
                                        Text("Select Event")
                                    }
                                    .font(.plusJakarta(.caption, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.leading, 6)

                            GlassyInputField(
                                icon: "trophy",
                                title: "Tournament Name",
                                content: AnyGlassyContent(TextFieldContent(text: $tournamentName, isReadOnly: true, textColor: .white)),
                                glassOpacity: 0.01,
                                labelColor: .gray,
                                materialOpacity: 0.2
                            )
                            
                            // Casino field
                            GlassyInputField(
                                icon: "building.2",
                                title: "Casino",
                                content: AnyGlassyContent(TextFieldContent(text: $tournamentCasino, keyboardType: .default, textColor: .white)),
                                glassOpacity: 0.01,
                                labelColor: .gray,
                                materialOpacity: 0.2
                            )
                            
                            // Tournament Game Type and Format Pickers - Side by Side
                            HStack(spacing: 12) {
                                // Tournament Game Type Picker
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "gamecontroller")
                                            .foregroundColor(.gray)
                                        Text("Game Type")
                                            .font(.plusJakarta(.caption, weight: .medium))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    HStack {
                                        ForEach(TournamentGameType.allCases, id: \.self) { gameType in
                                            Button(action: {
                                                selectedTournamentGameType = gameType
                                            }) {
                                                Text(gameType.displayName)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(selectedTournamentGameType == gameType ? .white : .gray)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 6)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .fill(selectedTournamentGameType == gameType ? Color.white.opacity(0.2) : Color.clear)
                                                    )
                                            }
                                        }
                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Material.ultraThinMaterial)
                                            .opacity(0.2)
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.01))
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                
                                // Tournament Format Picker
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "star.circle")
                                            .foregroundColor(.gray)
                                        Text("Format")
                                            .font(.plusJakarta(.caption, weight: .medium))
                                            .foregroundColor(.gray)
                                    }
                                    
                                    Picker("Tournament Format", selection: $selectedTournamentFormat) {
                                        ForEach(TournamentFormat.allCases, id: \.self) { format in
                                            Text(format.displayName).tag(format)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Material.ultraThinMaterial)
                                            .opacity(0.2)
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.01))
                                    }
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }

                            GlassyInputField(
                                icon: "dollarsign.circle",
                                title: "Buy in",
                                content: AnyGlassyContent(TextFieldContent(text: $baseBuyInTournament, keyboardType: .decimalPad, prefix: "$", textColor: .white, prefixColor: .gray)),
                                glassOpacity: 0.01,
                                labelColor: .gray,
                                materialOpacity: 0.2
                            )
                        }
                        .padding(.horizontal) // Padding for the tournament VStack
                    } // End of Tournament Setup Section

                    // Staking Section Trigger - NEW FLOATING POPUP
                    Button(action: {
                        // Add initial config if none exist
                        if stakerConfigs.isEmpty {
                            stakerConfigs.append(StakerConfig())
                        }
                        showingStakingPopup = true
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Staking Configuration")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(.white)
                                
                                if validStakerConfigs.isEmpty {
                                    Text("Tap to add stakers or configure stakes")
                                        .font(.plusJakarta(.caption, weight: .medium))
                                        .foregroundColor(.white.opacity(0.7))
                                } else {
                                    Text("\(validStakerConfigs.count) staker\(validStakerConfigs.count == 1 ? "" : "s") configured")
                                        .font(.plusJakarta(.caption, weight: .medium))
                                        .foregroundColor(.green.opacity(0.8))
                                }
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 8) {
                                if !validStakerConfigs.isEmpty {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 16))
                                }
                                
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.white.opacity(0.6))
                                    .font(.system(size: 14, weight: .medium))
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.white.opacity(0.6))
                                    .font(.system(size: 14, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Material.ultraThinMaterial)
                                .opacity(0.3)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(validStakerConfigs.isEmpty ? Color.white.opacity(0.2) : Color.green.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal)
                    
                    // Start Button Section - FIXED POSITIONING
                    VStack(spacing: 20) {
                        if selectedLogType == .cashGame {
                            // Start Button for Cash Game
                            if selectedGame != nil {
                                Button(action: startSession) {
                                    Text("Start Session")
                                        .font(.plusJakarta(.body, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(
                                            RoundedRectangle(cornerRadius: 27)
                                                .fill(buyIn.isEmpty ? Color.gray.opacity(0.3) : Color.gray.opacity(0.7))
                                                .background(.ultraThinMaterial)
                                                .clipShape(RoundedRectangle(cornerRadius: 27))
                                        )
                                }
                                .disabled(buyIn.isEmpty)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            }
                        } else {
                            // Start Button for Tournament
                            if !tournamentName.isEmpty && !baseBuyInTournament.isEmpty {
                                Button(action: startSession) {
                                    Text("Start Session")
                                        .font(.plusJakarta(.body, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 54)
                                        .background(
                                            RoundedRectangle(cornerRadius: 27)
                                                .fill(baseBuyInTournament.isEmpty ? Color.gray.opacity(0.3) : Color.gray.opacity(0.7))
                                                .background(.ultraThinMaterial)
                                                .clipShape(RoundedRectangle(cornerRadius: 27))
                                        )
                                }
                                .disabled(baseBuyInTournament.isEmpty)
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            }
                        }
                    }
                    
                    // Bottom spacing
                    Spacer()
                        .frame(height: 40)

                } // End of main content VStack for ScrollView
                .padding(.top, 5) // Reduced top padding for the content of ScrollView
                .padding(.bottom, 40) // Apply bottom padding to the content of ScrollView
            } // End of ScrollView
            .onTapGesture {
                // Also dismiss keyboard when tapping on ScrollView content
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        } // End of ZStack
        .sheet(isPresented: $showingAddGame) {
            AddCashGameView(cashGameService: cashGameService)
        }
        .alert("Delete Cash Game?", isPresented: $showingDeleteGameAlert, presenting: gameToDelete) { gameToDelete in // Ensure correct variable name here
            Button("Delete \(gameToDelete.name)", role: .destructive) {
                Task {
                    do {
                        try await cashGameService.deleteCashGame(gameToDelete)
                        // Optionally clear selection if the deleted game was selected
                        if selectedGame?.id == gameToDelete.id {
                            selectedGame = nil
                        }
                    } catch {

                        // Handle error (e.g., show another alert to the user)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { gameToDelete in // Ensure correct variable name here
            Text("Are you sure you want to delete the cash game \"\(gameToDelete.name) - \(formatStakes(game: gameToDelete))\"? This action cannot be undone.")
        }
        .sheet(isPresented: $showingEventSelector) {
            NavigationView {
                ExploreView(onEventSelected: { selectedEvent in
                    self.tournamentName = selectedEvent.event_name
                    
                    // Location and Type are no longer set from the event
                    // self.tournamentLocation = "" // REMOVED state variable
                    // self.selectedTournamentType = "NLH" // REMOVED state variable

                    if let usdBuyin = selectedEvent.buyin_usd {
                        self.baseBuyInTournament = String(format: "%.0f", usdBuyin)
                    } else if let parsedBuyin = parseBuyinToDouble(selectedEvent.buyin_string) {
                        self.baseBuyInTournament = String(format: "%.0f", parsedBuyin)
                    } else {
                        self.baseBuyInTournament = ""
                    }
                    
                    // Ensure casino update happens on main thread for UI refresh
                    DispatchQueue.main.async {
                        print("Debug: Selected event casino: '\(selectedEvent.casino ?? "nil")'")
                        self.tournamentCasino = selectedEvent.casino ?? ""
                        print("Debug: Tournament casino set to: '\(self.tournamentCasino)'")
                    }
                    
                    self.showingEventSelector = false
                }, isSheetPresentation: true)
                .environmentObject(sessionStore)
                .navigationTitle("Select Event")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Cancel") { showingEventSelector = false }
                            .foregroundColor(.white)
                    }
                }
            }
        }
    }
    
    // Helper function to format stakes
    private func formatStakes(game: CashGame) -> String {
        return game.stakes
    }
    
    // Game card with stakes and name
    private struct GameCard: View {
        let stakes: String
        let name: String
        let gameType: PokerVariant
        let isSelected: Bool
        var titleColor: Color = Color(white: 0.25)
        var subtitleColor: Color = Color(white: 0.4)
        var glassOpacity: Double = 0.01
        var materialOpacity: Double = 0.2
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stakes)
                            .font(.plusJakarta(.title3, weight: .bold))
                            .foregroundColor(titleColor)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        Text(name)
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(subtitleColor)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Spacer()
                    
                    // Game type badge
                    Text(gameType.displayName)
                        .font(.plusJakarta(.caption2, weight: .semibold))
                        .foregroundColor(titleColor.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.1))
                        )
                }
            }
            .frame(minWidth: 130)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    // Ultra-transparent glass effect
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    
                    // Almost invisible white overlay
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(glassOpacity))
                    
                    if isSelected {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white, lineWidth: 2)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // Add game button
    private struct AddGameButton: View {
        var textColor: Color = Color(white: 0.25)
        var glassOpacity: Double = 0.01
        var materialOpacity: Double = 0.2
        
        var body: some View {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(textColor)
                
                Text("Add")
                    .font(.plusJakarta(.body, weight: .medium))
                    .foregroundColor(textColor)
            }
            .frame(width: 130)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                ZStack {
                    // Ultra-transparent glass effect
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    
                    // Almost invisible white overlay
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(glassOpacity))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    // Protocol for glass content (if not already defined elsewhere)
    protocol GlassyContent {
        associatedtype ContentView: View
        @ViewBuilder var body: ContentView { get }
    }
    
    // Type-erased wrapper for GlassyContent
    struct AnyGlassyContent: View {
        private let content: AnyView
        
        init<T: GlassyContent>(_ content: T) {
            self.content = AnyView(content.body)
        }
        
        var body: some View {
            content
        }
    }
    
    struct TextFieldContent: GlassyContent {
        @Binding var text: String
        var keyboardType: UIKeyboardType = .default
        var prefix: String? = nil
        var isReadOnly: Bool = false
        var textColor: Color = Color(white: 0.25)
        var prefixColor: Color = Color(white: 0.4)
        
        var body: some View {
            HStack {
                if let prefix = prefix {
                    Text(prefix)
                        .font(.plusJakarta(.body, weight: .semibold))
                        .foregroundColor(prefixColor)
                }
                
                if isReadOnly {
                    Text(text)
                        .font(.plusJakarta(.body, weight: .regular))
                        .foregroundColor(textColor)
                } else {
                    TextField("0", text: $text)
                        .keyboardType(keyboardType)
                        .font(.plusJakarta(.body, weight: .regular))
                        .foregroundColor(textColor)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }
                            }
                        }
                }
            }
            .frame(height: 35)
        }
    }
    
    // Glassy input field with consistent styling
    struct GlassyInputField<Content: View>: View {
        let icon: String
        let title: String
        let content: Content
        var glassOpacity: Double = 0.01
        var labelColor: Color = Color(white: 0.4)
        var materialOpacity: Double = 0.2
        
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(labelColor)
                    Text(title)
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(labelColor)
                }
                
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    // Ultra-transparent glass effect
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    
                    // Almost invisible white overlay
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white.opacity(glassOpacity))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private func loadCashGames() {
        cashGameService.fetchCashGames()
    }
    
    private func startSession() {
        if selectedLogType == .cashGame {
            guard let game = selectedGame, let buyInAmount = Double(buyIn), buyInAmount > 0 else { return }
            sessionStore.startLiveSession(
                gameName: game.name,
                stakes: game.stakes,
                buyIn: buyInAmount,
                isTournament: false, // Explicitly false for cash games
                pokerVariant: game.gameType.rawValue // Pass the poker variant for cash games
            )
            isTournamentSession = false
            
            // Send session start notification for cash games - DISABLED
            // Task {
            //     do {
            //         try await sessionNotificationService.notifyCurrentUserSessionStart(
            //             sessionId: sessionStore.liveSession.id,
            //             gameName: game.name,
            //             stakes: game.stakes,
            //             buyIn: buyInAmount,
            //             startTime: sessionStore.liveSession.startTime,
            //             isTournament: false
            //         )
            //     } catch {
            //         print("[EnhancedLiveSessionView] Failed to send session start notification: \(error)")
            //     }
            // }
        } else {
            guard !tournamentName.isEmpty, let baseAmount = Double(baseBuyInTournament), baseAmount > 0 else { return }
            let tournamentStakesString: String // Explicitly declared as String
            if baseAmount > 0 {
                tournamentStakesString = "$\(Int(baseAmount)) Tournament"
            } else {
                tournamentStakesString = "Tournament"
            }
            sessionStore.startLiveSession(
                gameName: tournamentName, // This becomes the tournament name
                stakes: tournamentStakesString, // Simplified stakes string
                buyIn: baseAmount, // This is the base buy-in for the tournament
                isTournament: true,
                tournamentDetails: (name: tournamentName, type: "NLH", baseBuyIn: baseAmount), // Added placeholder type "NLH"
                tournamentGameType: selectedTournamentGameType,
                tournamentFormat: selectedTournamentFormat,
                casino: tournamentCasino
            )
            isTournamentSession = true
            baseBuyInForTournament = baseAmount
            
            // Send session start notification for tournaments - DISABLED
            // Task {
            //     do {
            //         try await sessionNotificationService.notifyCurrentUserSessionStart(
            //             sessionId: sessionStore.liveSession.id,
            //             gameName: tournamentName,
            //             stakes: tournamentStakesString,
            //             buyIn: baseAmount,
            //             startTime: sessionStore.liveSession.startTime,
            //             isTournament: true,
            //             tournamentName: tournamentName,
            //             casino: tournamentCasino.isEmpty ? nil : tournamentCasino
            //         )
            //     } catch {
            //         print("[EnhancedLiveSessionView] Failed to send tournament session start notification: \(error)")
            //     }
            // }
        }
        // Reset rebuy count
        tournamentRebuyCount = 0
        // Update UI mode
        sessionMode = .active

        // Ensure staker configs are preserved after session starts
        print("[EnhancedLiveSessionView] Session started with \(stakerConfigs.count) staker configs")
        stakerConfigsForPopup = stakerConfigs
        

        
        // Restore any missing staker profiles that might have been lost
        restoreMissingStakerProfiles()

        // Ensure "Session Started" activity appears immediately
        updateLocalDataFromStore()
    }
    
    // MARK: - Tab Content Views
    
    // Session Tab - Main session view with timer, stack, and quick actions
    private var sessionTabView: some View {
        ScrollView {
            VStack(spacing: 24) {
                timerSection
                    .padding(.horizontal)
                
                if isTournamentSession {
                    HStack(spacing: 12) { // HStack to hold Rebuy and Edit buttons
                        Button(action: addTournamentRebuy) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus.circle")
                                Text("Add Rebuy ($\(Int(baseBuyInForTournament)))")
                            }
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity) // Let it take available width
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.4)))
                        }
                        
                        // New Edit Total Buy-in Button for Tournaments
                        Button(action: {
                            editBuyInAmount = String(sessionStore.liveSession.buyIn)
                            showingEditBuyInSheet = true
                        }) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 22)) // Slightly larger for better tap target
                                .foregroundColor(.white.opacity(0.8))
                                .padding(12) // Adjust padding as needed
                                .background(Color.gray.opacity(0.25))
                                .clipShape(Circle())
                        }
                        .frame(width: 50) // Give it a defined width to balance with the rebuy button
                    }
                    .padding(.horizontal)
                } else {
                    chipStackSection
                        .padding(.horizontal)
                }
                
                // Session Challenge Progress Section
                if !challengeService.activeChallenges.filter({ $0.type == .session }).isEmpty {
                    liveSessionChallengeSection
                        .padding(.horizontal)
                }
                
                // Staking Information Section
                let shouldShowStaking = !existingStakes.isEmpty || !validStakerConfigs.isEmpty
                let _ = print("[EnhancedLiveSessionView] shouldShowStaking=\(shouldShowStaking), existingStakes=\(existingStakes.count), validStakerConfigs=\(validStakerConfigs.count)")
                
                if shouldShowStaking {
                    stakingInfoSection
                        .padding(.horizontal)
                }
                
                // Recent Updates Section (Chip / Notes / Hands)
                if !recentUpdates.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Activity")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding([.top, .leading, .trailing], 4)

                        ForEach(recentUpdates.prefix(4)) { item in
                            // Get the share action (will be nil for notes)
                            let shareAction = getShareAction(for: item)
                            
                            SessionUpdateCard(
                                title: item.title,
                                description: item.description,
                                timestamp: item.timestamp,
                                isPosted: false,
                                onPost: nil // Share to feed removed as per new requirements
                            )
                        }
                    }
                    .padding(12)
                    .glassyBackground(cornerRadius: 16)
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
                // Use combined chip updates for finding the update to share
                let combinedChipUpdates = self.combineChipUpdatesWithinTimeWindow(self.chipUpdates, timeWindow: 30)
                if let update = combinedChipUpdates.first(where: { $0.id == item.id }) {
                    let updateContent = "Stack update: $\(Int(update.amount))\(update.note != nil ? "\nNote: \(update.note!)" : "")"
                    self.showShareToFeedDialog(content: updateContent, isHand: false, handData: nil, updateId: update.id, isSharingChipUpdate: true)
                }
            } else if item.kind == .sessionStart {
                // For session start updates, share basic session info
                let postContent: String
                if self.isTournamentSession {
                    let buyText = self.baseBuyInForTournament > 0 ? "$\(Int(self.baseBuyInForTournament)) Buy-in" : "Tournament"
                    postContent = "Playing \(self.tournamentName) (\(buyText))"
                } else {
                    postContent = "Started a new session at \(self.sessionStore.liveSession.gameName) (\(self.sessionStore.liveSession.stakes))"
                }
                self.showShareToFeedDialog(content: postContent, isHand: false, isSharingSessionStart: true)
            }
        }
    }
    
    // Notes Tab - For viewing and adding notes
    private var notesTabView: some View {
        VStack(spacing: 0) {
            // Use a simple @State array that gets refreshed
            if displayNotes.isEmpty {
                emptyNotesView
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(Array(displayNotes.enumerated()).reversed(), id: \.offset) { index, note in
                            NoteCardView(noteText: note, onShareTapped: {
                                noteToShare = note
                                showingGroupSelection = true
                            })
                                .onTapGesture {
                                    self.noteToEditId = String(index)
                                    self.noteToEdit = note
                                    self.showingEditNoteSheet = true
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
        }
        .onAppear {
            refreshDisplayNotes()
        }
        .sheet(isPresented: $showingSimpleNoteEditor, onDismiss: {
            refreshDisplayNotes()
        }) { 
            SimpleNoteEditorView(sessionStore: sessionStore, sessionId: sessionStore.liveSession.id)
        }
        .sheet(isPresented: $showingGroupSelection) {
            if let noteToShare = noteToShare {
                GroupSelectionSheet(noteText: noteToShare) { group in
                    // Handle successful sharing
                    showingShareSuccess = true
                    shareSuccessMessage = "Note shared to \(group.name)"
                }
            }
        }
        .sheet(isPresented: $showingEditNoteSheet) {
            if let noteToEdit = noteToEdit, let noteIdStr = noteToEditId, let noteIndex = Int(noteIdStr) {
                EditNoteView(sessionStore: sessionStore, noteIndex: noteIndex, initialText: noteToEdit)
                    .onDisappear {
                        refreshDisplayNotes()
                        self.noteToEdit = nil
                        self.noteToEditId = nil
                    }
            } else {
                Text("Error loading note for editing.")
            }
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
            NavigationView {
                PostDetailView(post: post, userId: userId)
                    .environmentObject(postService)
                    .environmentObject(userService)
            }
            .navigationViewStyle(StackNavigationViewStyle())
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
                
                // Session stats - MODIFIED
                VStack(alignment: .trailing, spacing: 4) {
                    Text("TOTAL BUY-IN") // Changed label
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                    
                    Text("$\(Int(sessionStore.liveSession.buyIn))") // Display total buy-in
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white) // Profit/loss color removed
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(16)
            .glassyBackground(cornerRadius: 16)
            
            // Controls row
            VStack(spacing: 12) {
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
                        .glassyBackground(cornerRadius: 12)
                    }

                    Button(action: { 
                        cashoutAmount = String(Int(sessionStore.enhancedLiveSession.currentChipAmount))
                        showingCashoutPrompt = true 
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text("End")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glassyBackground(cornerRadius: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.red.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
                
                // Progress to Next Day button - only for tournaments
                if isTournamentSession {
                    Button(action: {
                        nextDayDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                        showingNextDayConfirmation = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "forward.circle.fill")
                            Text("Progress to Day \(sessionStore.liveSession.currentDay + 1)")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glassyBackground(cornerRadius: 12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
    
    // Chip stack graph section
    private var chipStackSection: some View {
        VStack(spacing: 20) {
            // Current Chip Stack Display
            VStack(spacing: 8) {
                Text("Current Chip Stack")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
                
                Text("$\(Int(sessionStore.enhancedLiveSession.currentChipAmount))")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .glassyBackground(cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            
            // Quick Update Buttons
            VStack(spacing: 12) {
                Text("Quick Update")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                            // First row: reds on left, greens on right
            HStack(spacing: 10) {
                QuickUpdateButton(amount: 5, isPositive: false, action: { quickUpdateChipStack(amount: -5) })
                QuickUpdateButton(amount: 25, isPositive: false, action: { quickUpdateChipStack(amount: -25) })
                QuickUpdateButton(amount: 5, isPositive: true, action: { quickUpdateChipStack(amount: 5) })
                QuickUpdateButton(amount: 25, isPositive: true, action: { quickUpdateChipStack(amount: 25) })
            }
            
            // Second row: reds on left, greens on right
            HStack(spacing: 10) {
                QuickUpdateButton(amount: 100, isPositive: false, action: { quickUpdateChipStack(amount: -100) })
                QuickUpdateButton(amount: 1000, isPositive: false, action: { quickUpdateChipStack(amount: -1000) })
                QuickUpdateButton(amount: 100, isPositive: true, action: { quickUpdateChipStack(amount: 100) })
                QuickUpdateButton(amount: 1000, isPositive: true, action: { quickUpdateChipStack(amount: 1000) })
            }
            }
            
            // Section Title
            Text("Session Actions")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Top row of action buttons
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
                    .glassyBackground(cornerRadius: 12)
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
                    .glassyBackground(cornerRadius: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                }
            }
            
            // Edit Buy-In button - styled differently to differentiate it
            Button(action: {
                // Prepare edit value and show the edit buy-in sheet
                editBuyInAmount = String(sessionStore.liveSession.buyIn)
                showingEditBuyInSheet = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 18))
                    Text("Edit Buy-in")
                        .font(.system(size: 15, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .glassyBackground(cornerRadius: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    // Quick Update Button Component
    private struct QuickUpdateButton: View {
        let amount: Int
        let isPositive: Bool
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Text("\(isPositive ? "+" : "-")$\(amount)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isPositive ? .green : .red)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .glassyBackground(cornerRadius: 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isPositive ? Color.green.opacity(0.5) : Color.red.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }
    
    // Quick Update Chip Stack Function
    private func quickUpdateChipStack(amount: Double) {
        let currentAmount = sessionStore.enhancedLiveSession.currentChipAmount
        let newAmount = currentAmount + amount
        
        // Generate appropriate note based on amount
        let note: String
        if amount > 0 {
            note = "Quick add: +$\(Int(amount))"
        } else {
            note = "Quick subtract: -$\(Int(abs(amount)))"
        }
        
        // Update the chip stack with the new total amount
        sessionStore.updateChipStack(amount: newAmount, note: note)
        
        // Update local data
        updateLocalDataFromStore()
    }
    
    // MARK: - Tournament Helpers
    private func addTournamentRebuy() {
        guard baseBuyInForTournament > 0 else { return }
        let oldBuyIn = sessionStore.liveSession.buyIn
        sessionStore.updateLiveSessionBuyIn(amount: baseBuyInForTournament)
        tournamentRebuyCount += 1
        
        // Send rebuy notification
        Task {
            do {
                try await sessionNotificationService.notifyCurrentUserRebuy(
                    sessionId: sessionStore.liveSession.id,
                    gameName: sessionStore.liveSession.tournamentName ?? tournamentName,
                    stakes: sessionStore.liveSession.stakes,
                    rebuyAmount: baseBuyInForTournament,
                    newTotalBuyIn: sessionStore.liveSession.buyIn,
                    isTournament: true,
                    tournamentName: sessionStore.liveSession.tournamentName ?? tournamentName
                )
            } catch {
                print("[EnhancedLiveSessionView] Failed to send tournament rebuy notification: \(error)")
            }
        }
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
            
            // MODIFIED: Handle staking like SessionFormView
            let finalBuyIn = self.sessionStore.liveSession.buyIn
            let finalCashout = cashout
            let profit = finalCashout - finalBuyIn
            let duration = formatDuration(self.sessionStore.liveSession.elapsedTime)
            
            // Set up session details for the share prompt
            await MainActor.run {
                self.sessionDetails = (
                    buyIn: finalBuyIn,
                    cashout: finalCashout,
                    profit: profit,
                    duration: duration,
                    gameName: self.sessionStore.liveSession.gameName,
                    stakes: self.sessionStore.liveSession.stakes,
                    sessionId: self.sessionStore.liveSession.id
                )
            }
            
            var sessionDataToSave: [String: Any] = [
                "userId": userId,
                "gameType": self.sessionStore.liveSession.isTournament ? SessionLogType.tournament.rawValue : SessionLogType.cashGame.rawValue,
                "gameName": self.sessionStore.liveSession.gameName,
                "stakes": self.sessionStore.liveSession.stakes,
                "startDate": Timestamp(date: self.sessionStore.liveSession.startTime),
                "startTime": Timestamp(date: self.sessionStore.liveSession.startTime),
                "endTime": Timestamp(date: Date()),
                "hoursPlayed": self.sessionStore.liveSession.elapsedTime / 3600,
                "buyIn": finalBuyIn,
                "cashout": finalCashout,
                "profit": profit,
                "createdAt": FieldValue.serverTimestamp(),
                "notes": self.sessionStore.enhancedLiveSession.notes,
                "liveSessionUUID": self.sessionStore.liveSession.id,
                "location": self.sessionStore.liveSession.isTournament ? (self.sessionStore.liveSession.tournamentName) : nil,
                "tournamentType": self.sessionStore.liveSession.isTournament ? self.sessionStore.liveSession.tournamentType : nil,
                "tournamentGameType": self.sessionStore.liveSession.isTournament ? self.sessionStore.liveSession.tournamentGameType?.rawValue : nil,
                "tournamentFormat": self.sessionStore.liveSession.isTournament ? self.sessionStore.liveSession.tournamentFormat?.rawValue : nil,
                "pokerVariant": !self.sessionStore.liveSession.isTournament ? self.sessionStore.liveSession.pokerVariant : nil, // Only save poker variant for cash games
            ]
            
            // Add casino for tournaments if provided
            if self.sessionStore.liveSession.isTournament, !self.tournamentCasino.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sessionDataToSave["casino"] = self.tournamentCasino
            }
            
            // Handle staking using the same logic as SessionFormView
            await self.handleStakingAndSave(
                sessionDataToSave: sessionDataToSave,
                gameNameForStake: self.sessionStore.liveSession.gameName,
                stakesForStake: self.sessionStore.liveSession.stakes,
                startDateTimeForStake: self.sessionStore.liveSession.startTime,
                sessionBuyInForStake: finalBuyIn,
                sessionCashout: finalCashout,
                isTournamentFlagForStake: self.sessionStore.liveSession.isTournament,
                tournamentTotalInvestmentForStake: self.sessionStore.liveSession.isTournament ? finalBuyIn : nil,
                tournamentNameForStake: self.sessionStore.liveSession.isTournament ? self.sessionStore.liveSession.tournamentName : nil
            )
        }
    }
    
    // Helper function to format duration 
    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = (Int(timeInterval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    // COPIED FROM SessionFormView: Unified function to handle staking and saving
    private func handleStakingAndSave(
        sessionDataToSave: [String: Any],
        gameNameForStake: String,
        stakesForStake: String,
        startDateTimeForStake: Date,
        sessionBuyInForStake: Double, 
        sessionCashout: Double,
        isTournamentFlagForStake: Bool,
        tournamentTotalInvestmentForStake: Double?,
        tournamentNameForStake: String?
    ) async {
        let actualBuyInForStaking = tournamentTotalInvestmentForStake ?? sessionBuyInForStake

        // Filter out configs that are truly empty or invalid before deciding to save session only or with stakes.
        let validConfigs = stakerConfigs.filter { config in
            if config.isManualEntry {
                guard config.selectedManualStaker != nil else { return false }
            } else {
                guard let _ = config.selectedStaker else { return false }
            }
            guard let percentage = Double(config.percentageSold), percentage > 0, percentage <= 100 else { return false }
            guard let markup = Double(config.markup), markup >= 1.0 else { return false }
            guard actualBuyInForStaking > 0 else { 
                return percentage == 0
            }
            return true
        }

        if validConfigs.isEmpty {
            // If no valid staking configurations are provided (either stakerConfigs is empty or all entries are invalid)

            await saveSessionDataOnly(sessionData: sessionDataToSave)
        } else {
            // If there are valid staking configurations

            await saveSessionDataAndIndividualStakes(
                sessionData: sessionDataToSave,
                gameName: gameNameForStake,
                stakes: stakesForStake,
                startDateTime: startDateTimeForStake,
                actualSessionBuyInForStaking: actualBuyInForStaking,
                sessionCashout: sessionCashout,
                tournamentName: tournamentNameForStake,
                isTournamentStake: isTournamentFlagForStake,
                configs: validConfigs // Pass the array of valid configs
            )
        }
    }

    // COPIED FROM SessionFormView
    private func saveSessionDataOnly(sessionData: [String: Any]) async {
        do {
            let docRef = try await Firestore.firestore().collection("sessions").addDocument(data: sessionData)
            
            // Create a Session object from the saved data for challenge updates
            let session = Session(id: docRef.documentID, data: sessionData)
            
            // Update session challenges
            await challengeService.updateSessionChallengesFromSession(session)
            
            // Update sessionDetails with the saved session ID
            await MainActor.run {
                if var details = self.sessionDetails {
                    details.sessionId = docRef.documentID
                    self.sessionDetails = details
                }
                
                self.sessionStore.endAndClearLiveSession()
                self.isLoadingSave = false
                
                // Show session result share view instead of simple prompt
                self.sharingFlowState = .resultShare
            }
        } catch {

            await MainActor.run {
                self.isLoadingSave = false
            }
        }
    }

    // COPIED FROM SessionFormView
    private func saveSessionDataAndIndividualStakes(
        sessionData: [String: Any],
        gameName: String,
        stakes: String,
        startDateTime: Date,
        actualSessionBuyInForStaking: Double,
        sessionCashout: Double,
        tournamentName: String?,
        isTournamentStake: Bool,
        configs: [StakerConfig] // Takes an array of StakerConfig
    ) async {
        let newDocumentId = Firestore.firestore().collection("sessions").document().documentID
        var mutableSessionData = sessionData
        mutableSessionData["id"] = newDocumentId

        do {
            try await Firestore.firestore().collection("sessions").document(newDocumentId).setData(mutableSessionData)
            
            // Create a Session object from the saved data for challenge updates
            let session = Session(id: newDocumentId, data: mutableSessionData)
            
            // Update session challenges
            await challengeService.updateSessionChallengesFromSession(session)
            
            // Now handle stakes - update existing ones or create new ones
            var allStakesSuccessful = true
            var savedStakeCount = 0

            for config in configs {
                guard let percentageSoldDouble = Double(config.percentageSold),
                      let markupDouble = Double(config.markup) else {
                    allStakesSuccessful = false
                    continue
                }

                let stakerIdToUse: String
                let manualName: String?
                let isOffApp: Bool

                if config.isManualEntry {
                    guard let selectedManualStaker = config.selectedManualStaker else {
                        allStakesSuccessful = false
                        continue
                    }
                    stakerIdToUse = selectedManualStaker.id ?? Stake.OFF_APP_STAKER_ID
                    manualName = selectedManualStaker.name
                    isOffApp = true
                } else if let stakerProfile = config.selectedStaker {
                    stakerIdToUse = stakerProfile.id
                    manualName = nil
                    isOffApp = false
                } else {
                    allStakesSuccessful = false
                    continue
                }

                                 // NEW: Check if this config has an existing stake ID to update
                 if let originalStakeId = config.originalStakeId {
                     // UPDATE existing stake with session data
                     print("[EnhancedLiveSessionView] Updating existing stake ID: \(originalStakeId)")
                    do {
                        // Calculate the settlement amount using the correct formula
                        let stakerCost = actualSessionBuyInForStaking * (percentageSoldDouble / 100.0) * markupDouble
                        let stakerShareOfCashout = sessionCashout * (percentageSoldDouble / 100.0)
                        let settlementAmount = stakerShareOfCashout - stakerCost
                        
                        let updateData: [String: Any] = [
                            Stake.CodingKeys.sessionId.rawValue: newDocumentId,
                            Stake.CodingKeys.totalPlayerBuyInForSession.rawValue: actualSessionBuyInForStaking,
                            Stake.CodingKeys.playerCashoutForSession.rawValue: sessionCashout,
                            Stake.CodingKeys.storedAmountTransferredAtSettlement.rawValue: settlementAmount,
                            Stake.CodingKeys.lastUpdatedAt.rawValue: Timestamp(date: Date()),
                            Stake.CodingKeys.status.rawValue: Stake.StakeStatus.awaitingSettlement.rawValue
                        ]
                        
                                                 try await stakeService.updateStake(stakeId: originalStakeId, updateData: updateData)
                        savedStakeCount += 1
                        print("[EnhancedLiveSessionView] Successfully updated existing stake")
                    } catch {
                        print("[EnhancedLiveSessionView] Failed to update existing stake: \(error)")
                        allStakesSuccessful = false
                    }
                } else {
                    // CREATE new stake
                    print("[EnhancedLiveSessionView] Creating new stake for staker: \(stakerIdToUse)")
                    
                    // Calculate the settlement amount for this stake
                    let profit = sessionCashout - actualSessionBuyInForStaking
                    let stakerShare = profit * (percentageSoldDouble / 100.0)
                    let adjustedStakerShare = stakerShare * markupDouble
                    let settlementAmount = -adjustedStakerShare // Negative means player pays staker
                    
                    let newStake = Stake(
                        sessionId: newDocumentId,
                        sessionGameName: tournamentName ?? gameName,
                        sessionStakes: stakes,
                        sessionDate: startDateTime,
                        stakerUserId: stakerIdToUse,
                        stakedPlayerUserId: self.userId,
                        stakePercentage: percentageSoldDouble / 100.0,
                        markup: markupDouble,
                        totalPlayerBuyInForSession: actualSessionBuyInForStaking,
                        playerCashoutForSession: sessionCashout,
                        storedAmountTransferredAtSettlement: settlementAmount,
                        isTournamentSession: isTournamentStake,
                        manualStakerDisplayName: manualName,
                        isOffAppStake: isOffApp
                    )
                    do {
                        _ = try await stakeService.addStake(newStake)
                        savedStakeCount += 1
                        print("[EnhancedLiveSessionView] Successfully created new stake")
                    } catch {
                        print("[EnhancedLiveSessionView] Failed to create new stake: \(error)")
                        allStakesSuccessful = false
                    }
                }
            }

            await MainActor.run {
                // Update sessionDetails with the saved session ID
                if var details = self.sessionDetails {
                    details.sessionId = newDocumentId
                    self.sessionDetails = details
                }
                
                self.sessionStore.endAndClearLiveSession()
                self.isLoadingSave = false
                if allStakesSuccessful && savedStakeCount == configs.count && savedStakeCount > 0 {
                    print("[EnhancedLiveSessionView] All stakes processed successfully (\(savedStakeCount) total)")
                } else if savedStakeCount > 0 {
                    print("[EnhancedLiveSessionView] Partial success: \(savedStakeCount) of \(configs.count) stakes processed")
                } else {
                    print("[EnhancedLiveSessionView] Failed to process stakes")
                }
                
                // Show session result share view instead of simple prompt
                self.sharingFlowState = .resultShare
            }
        } catch {
            print("[EnhancedLiveSessionView] Failed to save session: \(error)")
            await MainActor.run {
                self.isLoadingSave = false
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
    private func showShareToFeedDialog(
        content: String,
        isHand: Bool,
        handData: ParsedHandHistory? = nil,
        updateId: String? = nil,
        isSharingNote: Bool = false,
        isSharingChipUpdate: Bool = false,
        isSharingSessionStart: Bool = false
    ) {
        // First store what's being shared
        if isSharingNote {
            self.shareToFeedContent = content // Keep the original note content without prefixing
        } else {
            self.shareToFeedContent = isHand ? "" : content
        }
        self.shareToFeedIsHand = isHand
        self.shareToFeedHandData = handData
        self.shareToFeedUpdateId = updateId
        
        // Store the content type for use in the editor
        self.shareToFeedIsNote = isSharingNote
        self.shareToFeedIsChipUpdate = isSharingChipUpdate
        self.shareToFeedIsSessionStart = isSharingSessionStart
        
        // Show the post editor dialog
        if userService.currentUserProfile != nil {
            // Make sure post editor is properly set up
            showingLiveSessionPostEditor = true
        } else {
            // If user profile is not available, prompt user to log in
            showingNoProfileAlert = true
        }
    }
    
    // Simple function to refresh notes display
    private func refreshDisplayNotes() {
        displayNotes = sessionStore.enhancedLiveSession.notes
    }
    
    // Update local data from store
    private func updateLocalDataFromStore() {
        chipUpdates = sessionStore.enhancedLiveSession.chipUpdates
        notes = sessionStore.enhancedLiveSession.notes
        
        // Also refresh display notes
        refreshDisplayNotes()

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
        
        // Combine chip updates within 30 seconds and convert to UpdateItems
        let combinedChipUpdates = combineChipUpdatesWithinTimeWindow(chipUpdates, timeWindow: 30)
        for chip in combinedChipUpdates {
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
    
    // REMOVED: Function to check for new hands - disabled for launch
    // private func checkForNewHands() {
    //     // Hand functionality removed for launch
    // }
    
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
    

    
    // Live session post editor sheet for during-session sharing
    private var liveSessionPostEditorSheet: some View {
        Group {
            // Get session info for badge
            let gameName = sessionStore.liveSession.gameName
            let stakes = sessionStore.liveSession.stakes
            
            // For notes or hands during the session, show BADGE (not full card)
            if shareToFeedIsNote || shareToFeedIsHand {
                PostEditorView(
                    userId: userId,
                    initialText: shareToFeedContent,
                    initialHand: shareToFeedHandData,
                    sessionId: sessionStore.liveSession.id,
                    isSessionPost: true,
                    isNote: shareToFeedIsNote,
                    showFullSessionCard: false,  // Just show badge for notes/hands
                    sessionGameName: isTournamentSession ? (sessionStore.liveSession.tournamentName ?? gameName) : gameName,  // Pass game name directly
                    sessionStakes: isTournamentSession ? "$\(Int(baseBuyInForTournament)) Buy-in" : stakes  // For tournaments, just show buy-in
                )
            }
            // For session start posts
            else if shareToFeedIsSessionStart {
                PostEditorView(
                    userId: userId,
                    initialText: shareToFeedContent, // This is the "Started session..." message
                    initialHand: nil,
                    sessionId: sessionStore.liveSession.id,
                    isSessionPost: true,
                    isNote: false,
                    showFullSessionCard: true, // Show full card for session start
                    sessionGameName: isTournamentSession ? (sessionStore.liveSession.tournamentName ?? gameName) : gameName,
                    sessionStakes: isTournamentSession ? "$\(Int(baseBuyInForTournament)) Buy-in" : stakes
                )
            }
            // For chip updates, show the FULL session card
            else if shareToFeedIsChipUpdate {
                let effectiveGameName = isTournamentSession ? (sessionStore.liveSession.tournamentName ?? gameName) : gameName
                let effectiveStakes = isTournamentSession ? "Rebuy/Add-on ($\(Int(baseBuyInForTournament)))" : stakes

                PostEditorView(
                    userId: userId,
                    initialText: getSessionDetailsText() + "\n\n" + shareToFeedContent,
                    initialHand: nil,
                    sessionId: sessionStore.liveSession.id,
                    isSessionPost: true,
                    isNote: false,
                    showFullSessionCard: true,  // Show full card for chip updates
                    sessionGameName: effectiveGameName,
                    sessionStakes: effectiveStakes
                )
            }
            // Default case
            else {
                PostEditorView(
                    userId: userId,
                    initialText: getSessionDetailsText() + "\n\n" + shareToFeedContent,
                    initialHand: shareToFeedHandData,
                    sessionId: sessionStore.liveSession.id,
                    isSessionPost: true,
                    isNote: false,
                    showFullSessionCard: !shareToFeedIsNote && !shareToFeedIsHand,
                    sessionGameName: isTournamentSession ? (sessionStore.liveSession.tournamentName ?? gameName) : gameName,
                    sessionStakes: isTournamentSession ? "$\(Int(baseBuyInForTournament)) Buy-in" : stakes
                )
            }
        }
        .environmentObject(postService)
        .environmentObject(userService)
        .environmentObject(sessionStore)
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
        
        // Don't dismiss the session view here - only dismiss for completed sessions
    }
    
    // Add new sheet for rebuy amount
    private var rebuyView: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Add Rebuy")
                            .font(.plusJakarta(.title3, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { 
                            showingRebuySheet = false
                            showEditBuyIn = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // Rebuy amount field
                     GlassyInputField(
                         icon: "plus.circle",
                         title: "Rebuy Amount",
                         content: AnyGlassyContent(TextFieldContent(
                             text: $rebuyAmount,
                             keyboardType: .decimalPad,
                             prefix: "$",
                             textColor: .white,
                             prefixColor: .gray
                         )),
                         glassOpacity: 0.01,
                         labelColor: .gray,
                         materialOpacity: 0.2
                     )
                     
                     Spacer()
                     
                     // Submit button
                     Button(action: {
                         handleRebuy()
                         showingRebuySheet = false
                     }) {
                         Text("Add Rebuy")
                             .font(.plusJakarta(.body, weight: .bold))
                             .foregroundColor(.black)
                             .frame(maxWidth: .infinity)
                             .padding(.vertical, 16)
                        .background(
                                 RoundedRectangle(cornerRadius: 20)
                                     .fill(isValidRebuyAmount() ? Color.white : Color.white.opacity(0.5))
                             )
                     }
                     .disabled(!isValidRebuyAmount())
                 }
                 .padding(24)
                 .frame(maxWidth: .infinity, maxHeight: geometry.size.height, alignment: .top)
             }
             .onTapGesture {
                 UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
             }
         }
     }
     
     // New view for editing buy-in amount
     
     private var editBuyInView: some View {
         GeometryReader { geometry in
             ZStack {
                 AppBackgroundView()
                     .ignoresSafeArea()
                     .onTapGesture {
                         UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                     }
                 
                 VStack(spacing: 24) {
                     // Header
                                HStack {
                                    Text("Edit Buy-in")
                             .font(.plusJakarta(.title3, weight: .bold))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                         Button(action: { showingEditBuyInSheet = false }) {
                             Image(systemName: "xmark.circle.fill")
                                 .font(.system(size: 24))
                                        .foregroundColor(.gray)
                                }
                     }
                     
                     // Total Buy-in amount field
                     VStack(alignment: .leading, spacing: 16) {
                         Text("Current total buy-in: $\(Int(sessionStore.liveSession.buyIn))")
                             .font(.plusJakarta(.subheadline, weight: .medium))
                                            .foregroundColor(.gray)
                             .padding(.leading, 4)
                         
                         GlassyInputField(
                             icon: "dollarsign.square",
                             title: "New Total Buy-in Amount",
                             content: AnyGlassyContent(TextFieldContent(
                                 text: $editBuyInAmount,
                                 keyboardType: .decimalPad,
                                 prefix: "$",
                                 textColor: .white,
                                 prefixColor: .gray
                             )),
                             glassOpacity: 0.01,
                             labelColor: .gray,
                             materialOpacity: 0.2
                         )
                         
                         Text("This will update your session's total buy-in amount.")
                             .font(.plusJakarta(.caption, weight: .regular))
                             .foregroundColor(.gray)
                             .padding(.leading, 4)
                     }
                     
                     Spacer()
                     
                     // Submit button
                                    Button(action: {
                                        if let amount = Double(editBuyInAmount.trimmingCharacters(in: .whitespacesAndNewlines)), amount > 0 {
                                            sessionStore.setTotalBuyIn(amount: amount)
                                            updateLocalDataFromStore()
                             showingEditBuyInSheet = false
                                        }
                                    }) {
                                        Text("Update Buy-in")
                             .font(.plusJakarta(.body, weight: .bold))
                                            .foregroundColor(.black)
                                            .frame(maxWidth: .infinity)
                             .padding(.vertical, 16)
                                            .background(
                                 RoundedRectangle(cornerRadius: 20)
                                     .fill(isValidEditBuyInAmount() ? Color.white : Color.white.opacity(0.5))
                             )
                     }
                     .disabled(!isValidEditBuyInAmount())
                 }
                 .padding(24)
                 .frame(maxWidth: .infinity, maxHeight: geometry.size.height, alignment: .top)
             }
             .onTapGesture {
                 UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
             }
         }
     }
     
     // Helper method for edit buy-in validation
     private func isValidEditBuyInAmount() -> Bool {
         guard let amount = Double(editBuyInAmount.trimmingCharacters(in: .whitespacesAndNewlines)),
               amount > 0 else {
             return false
         }
         return true
     }
     
     // MARK: - Next Day Confirmation Sheet
    
    private var nextDayConfirmationSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                            .padding(.bottom, 4)
                        
                        Text("Progress to Day \(sessionStore.liveSession.currentDay + 1)")
                            .font(.plusJakarta(.title2, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("This will pause your current session and create a reminder for the next day. All your session data will be preserved.")
                            .font(.plusJakarta(.callout, weight: .regular))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    .padding(.top, 20)
                    
                    VStack(spacing: 12) {
                        Text("Select Date for Day \(sessionStore.liveSession.currentDay + 1)")
                            .font(.plusJakarta(.headline, weight: .medium))
                            .foregroundColor(.white)
                        
                        DatePicker(
                            "Next Day Date",
                            selection: $nextDayDate,
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .colorScheme(.dark)
                        .frame(minHeight: 300) // Give the calendar enough space
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Material.ultraThinMaterial)
                                .opacity(0.2)
                        )
                        .padding(.horizontal, 20)
                    }
                    
                    VStack(spacing: 12) {
                        Button(action: {
                            print("🔥🔥🔥 [NextDay Button] Confirm & Progress button tapped!")
                            Task {
                                print("🔥🔥🔥 [NextDay Button] Task started")
                                // Save current stakes to Firestore BEFORE pausing
                                await saveStakesForPause()
                                
                                // Create the resume event
                                let success = await sessionStore.createResumeEvent(for: nextDayDate)
                                
                                await MainActor.run {
                                    if success {
                                        // Pause the session for next day (stakes are now saved in Firestore)
                                        sessionStore.pauseForNextDay(nextDayDate: nextDayDate)
                                        showingNextDayConfirmation = false
                                        
                                        // Auto-dismiss the session view after pausing
                                        dismiss()
                                    }
                                }
                            }
                        }) {
                            Text("Confirm & Progress")
                                .font(.plusJakarta(.body, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.blue)
                                )
                        }
                        
                        Button(action: {
                            showingNextDayConfirmation = false
                        }) {
                            Text("Cancel")
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .background(AppBackgroundView().ignoresSafeArea())
            .navigationTitle("Progress Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        showingNextDayConfirmation = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    // Add helper methods that were accidentally removed
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
        
        // Send rebuy notification for cash games
        Task {
            do {
                try await sessionNotificationService.notifyCurrentUserRebuy(
                    sessionId: sessionStore.liveSession.id,
                    gameName: sessionStore.liveSession.gameName,
                    stakes: sessionStore.liveSession.stakes,
                    rebuyAmount: amount,
                    newTotalBuyIn: sessionStore.liveSession.buyIn,
                    isTournament: false
                )
            } catch {
                print("[EnhancedLiveSessionView] Failed to send cash game rebuy notification: \(error)")
            }
        }
        
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

            return
        }
        
        isLoadingSessionPosts = true

        
        Task {
            let posts = await postService.getSessionPosts(sessionId: sessionStore.liveSession.id)

            
            await MainActor.run {
                sessionPosts = posts
                isLoadingSessionPosts = false
            }
        }
    }
    
    // Refresh session posts
    private func refreshSessionPosts() async {
        guard !sessionStore.liveSession.id.isEmpty else {

            return
        }
        
        isLoadingSessionPosts = true

        
        let posts = await postService.getSessionPosts(sessionId: sessionStore.liveSession.id)

        
        await MainActor.run {
            sessionPosts = posts
            isLoadingSessionPosts = false
        }
    }
    
    // Add helper method to show post detail
    private func showPostDetail(_ post: Post) {
        selectedPost = post
    }
    
    // MARK: - New Sharing Options Views
    
    // MARK: - Glassy Action Button
    struct GlassyActionButton: View {
        let title: String
        let systemImage: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text(title)
                        .font(.plusJakarta(.headline, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Material.ultraThinMaterial)
                            .opacity(0.25)
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.05))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    // Update postShareOptionsSheet
    private var postShareOptionsSheet: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    GlassyActionButton(title: "Share Session Start", systemImage: "figure.play") {
                        let postContent = "Started a new session at \(sessionStore.liveSession.gameName) (\(sessionStore.liveSession.stakes))"
                        showShareToFeedDialog(
                            content: postContent,
                            isHand: false,
                            isSharingSessionStart: true
                        )
                        showingPostShareOptions = false
                    }

                    // REMOVED: Share a Hand button
                    /*
                    GlassyActionButton(title: "Share a Hand", systemImage: "suit.spade.fill") {
                        showingShareHandSelector = true
                        showingPostShareOptions = false
                    }
                    */

                    GlassyActionButton(title: "Share a Note", systemImage: "note.text") {
                        showingShareNoteSelector = true
                        showingPostShareOptions = false
                    }

                    GlassyActionButton(title: "Share Rebuy / Chip Update", systemImage: "dollarsign.circle.fill") {
                        showingShareChipUpdateSelector = true
                        showingPostShareOptions = false
                    }

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingPostShareOptions = false }
                        .foregroundColor(.white)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .accentColor(.white)
    }

    // Update shareNoteSelectorSheet to use NoteCardView
    private var shareNoteSelectorSheet: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Add explanation text at the top
                        Text("Select a note to share. Notes will be posted with your current session tag.")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.bottom, 16)
                        
                        if notes.isEmpty {
                            VStack {
                                Spacer()
                                Text("No notes recorded for this session yet.")
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                Spacer()
                            }
                            .frame(height: 300)
                        } else {
                            ForEach(notes.indices.reversed(), id: \.self) { index in
                                let note = notes[index]
                                Button(action: {
                                    showShareToFeedDialog(
                                        content: note,
                                        isHand: false,
                                        updateId: "note_\(index)",
                                        isSharingNote: true
                                    )
                                    showingShareNoteSelector = false
                                }) {
                                    NoteCardView(noteText: note)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 120)
                }
            }
            .navigationTitle("Select Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingShareNoteSelector = false }
                        .foregroundColor(.white)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .accentColor(.white)
    }

    // REMOVED: shareHandSelectorSheet - hand functionality disabled for launch

    // Update shareChipUpdateSelectorSheet to use SessionUpdateCard style
    private var shareChipUpdateSelectorSheet: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Use combined chip updates for sharing
                        let combinedChipUpdates = combineChipUpdatesWithinTimeWindow(chipUpdates, timeWindow: 30)
                        let relevantChipUpdates = combinedChipUpdates
                            .filter { chipUpdate in
                                let isRebuy = chipUpdate.note?.lowercased().contains("rebuy") == true
                                let previousAmount: Double
                                if let index = combinedChipUpdates.firstIndex(where: { $0.id == chipUpdate.id }), index > 0 {
                                    previousAmount = combinedChipUpdates[index - 1].amount
                                } else {
                                    previousAmount = sessionStore.liveSession.buyIn
                                }
                                let isSignificantChange = abs(chipUpdate.amount - previousAmount) > 50
                                return isRebuy || isSignificantChange
                            }
                            .sorted(by: { $0.timestamp > $1.timestamp })

                        if relevantChipUpdates.isEmpty {
                            VStack {
                                Spacer()
                                Text("No rebuys or significant chip updates recorded yet.")
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                Spacer()
                            }
                            .frame(height: 300)
                        } else {
                            ForEach(relevantChipUpdates) { update in
                                Button(action: {
                                    let updateContent = "Stack update: $\(Int(update.amount))\(update.note != nil ? "\nNote: \(update.note!)" : "")"
                                    showShareToFeedDialog(
                                        content: updateContent,
                                        isHand: false,
                                        updateId: update.id,
                                        isSharingChipUpdate: true
                                    )
                                    showingShareChipUpdateSelector = false
                                }) {
                                    SessionUpdateCard(
                                        title: "Stack: $\(Int(update.amount))",
                                        description: update.note ?? "Chip update",
                                        timestamp: update.timestamp,
                                        isPosted: false,
                                        onPost: nil
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 120)
                }
            }
            .navigationTitle("Select Chip Update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showingShareChipUpdateSelector = false }
                        .foregroundColor(.white)
                }
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .accentColor(.white)
    }

    // MARK: - Tournament Utility Functions
    private func parseBuyinToDouble(_ buyinString: String) -> Double? {
        let currencySymbols = CharacterSet(charactersIn: "$,€£¥")
        var cleaned = buyinString.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.components(separatedBy: currencySymbols).joined()
        cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        if let mainPart = cleaned.split(whereSeparator: { "+-/".contains($0) }).first {
            cleaned = String(mainPart)
        }
        return Double(cleaned)
    }

    // Function to load existing stakes for this session
    private func loadExistingStakes() {
        guard !sessionStore.liveSession.id.isEmpty else { 
            print("🔥🔥🔥 [loadExistingStakes] Empty session ID, returning")
            return 
        }
        
        print("🔥🔥🔥 [loadExistingStakes] Loading stakes for session ID: \(sessionStore.liveSession.id)")
        isLoadingStakes = true
        Task {
            do {
                print("🔥🔥🔥 [loadExistingStakes] Calling fetchStakesForLiveSession with ID: \(sessionStore.liveSession.id)")
                var stakes = try await stakeService.fetchStakesForLiveSession(sessionStore.liveSession.id)
                print("🔥🔥🔥 [loadExistingStakes] Received \(stakes.count) stakes from liveSession query")
                
                // If no stakes found for live session, also check for event-based stakes
                // This handles the case where stakes were created from an event before starting the live session
                if stakes.isEmpty, let preselectedEvent = preselectedEvent {
                    print("🔥🔥🔥 [loadExistingStakes] No stakes found for liveSession, checking for event stakes")
                    let allUserStakes = try await stakeService.fetchStakes(forUser: userId)
                    let eventStakes = allUserStakes.filter { stake in
                        stake.sessionGameName == preselectedEvent.event_name &&
                        stake.stakedPlayerUserId == userId &&
                        stake.status == .active &&
                        stake.totalPlayerBuyInForSession == 0 &&
                        stake.playerCashoutForSession == 0
                    }
                    stakes = eventStakes
                    print("🔥🔥🔥 [loadExistingStakes] Found \(eventStakes.count) event-based stakes for '\(preselectedEvent.event_name)'")
                }
                
                await MainActor.run {
                    print("🔥🔥🔥 [loadExistingStakes] MainActor run - setting existingStakes to \(stakes.count) stakes")
                    self.existingStakes = stakes
                    
                    // Convert existing stakes to StakerConfigs for editing
                    self.stakerConfigs = stakes.compactMap { stake -> StakerConfig? in
                        // Only include stakes where current user is the staked player
                        guard stake.stakedPlayerUserId == self.userId else { return nil }
                        
                        var config = StakerConfig()
                        config.markup = String(stake.markup)
                        config.percentageSold = String(stake.stakePercentage * 100) // Convert back to percentage
                        
                        // Store the original stake ID and user ID for updating
                        config.originalStakeId = stake.id
                        config.originalStakeUserId = stake.stakerUserId
                        
                        // Handle manual vs app stakers
                        if stake.isOffAppStake ?? false {
                            // This is a manual staker - try to load the manual staker profile
                            config.isManualEntry = true
                            
                            // Try to load manual staker profile
                            Task {
                                do {
                                    let manualStakerProfile = try await manualStakerService.getManualStaker(id: stake.stakerUserId)
                                    await MainActor.run {
                                        if let index = self.stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                                            self.stakerConfigs[index].selectedManualStaker = manualStakerProfile
                                        }
                                    }
                                } catch {
                                    // If we can't load the profile, fall back to legacy display name
                                    await MainActor.run {
                                        if let index = self.stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                                            self.stakerConfigs[index].manualStakerName = stake.manualStakerDisplayName ?? "Unknown Manual Staker"
                                        }
                                    }
                                }
                            }
                        } else {
                            // This is an app user staker
                            config.isManualEntry = false
                            
                            // Try to load the staker's profile
                            if let stakerProfile = self.userService.loadedUsers[stake.stakerUserId] {
                                config.selectedStaker = stakerProfile
                            } else {
                                // Load staker profile asynchronously
                                Task {
                                    await self.userService.fetchUser(id: stake.stakerUserId)
                                    await MainActor.run {
                                        if let fetchedProfile = self.userService.loadedUsers[stake.stakerUserId] {
                                            // Update the config with the loaded profile
                                            if let index = self.stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                                                self.stakerConfigs[index].selectedStaker = fetchedProfile
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        return config
                    }
                    
                    // Also sync the popup configs
                    self.stakerConfigsForPopup = self.stakerConfigs
                    
                    print("🔥🔥🔥 [loadExistingStakes] Final result - stakerConfigs: \(self.stakerConfigs.count), stakerConfigsForPopup: \(self.stakerConfigsForPopup.count)")
                    
                    self.isLoadingStakes = false
                    
                    // --- Fallback: if no stakes were found, attempt to restore from local cache ---
                    if stakes.isEmpty {
                        if let cachedData = UserDefaults.standard.data(forKey: "StakerConfigs_\(sessionStore.liveSession.id)"),
                           let cachedConfigs = try? JSONDecoder().decode([StakerConfig].self, from: cachedData) {
                            print("🔥🔥🔥 [loadExistingStakes] Restoring \(cachedConfigs.count) staker configs from local cache")
                            self.stakerConfigs = cachedConfigs
                            self.stakerConfigsForPopup = cachedConfigs
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoadingStakes = false
                    print("Error loading stakes: \(error)")
                }
            }
        }
    }
    
    // Function to save current stakes when pausing for next day
    private func saveStakesForPause() async {
        print("🔥🔥🔥 [saveStakesForPause] Starting - session ID: \(sessionStore.liveSession.id)")
        print("🔥🔥🔥 [saveStakesForPause] Current stakerConfigs count: \(stakerConfigs.count)")
        print("🔥🔥🔥 [saveStakesForPause] Saving current stakes to Firestore")
        
        // Filter out configs that are truly empty or invalid
        let validConfigs = stakerConfigs.filter { config in
            if config.isManualEntry {
                guard config.selectedManualStaker != nil || !config.manualStakerName.isEmpty else { return false }
            } else {
                guard config.selectedStaker != nil else { return false }
            }
            guard let percentage = Double(config.percentageSold), percentage > 0, percentage <= 100 else { return false }
            guard let markup = Double(config.markup), markup >= 1.0 else { return false }
            return true
        }
        
        guard !validConfigs.isEmpty else {
            print("[EnhancedLiveSessionView] No valid staking configs to save")
            return
        }
        
        print("[EnhancedLiveSessionView] Saving \(validConfigs.count) valid staking configs")
        
        // Debug: Log each config's originalStakeId
        for (index, config) in validConfigs.enumerated() {
            print("[EnhancedLiveSessionView] Config \(index): originalStakeId = '\(config.originalStakeId ?? "nil")', isManualEntry = \(config.isManualEntry)")
        }
        
        // Use the existing logic from saveSessionDataAndIndividualStakes but just save stakes
        for config in validConfigs {
            guard let percentageSoldDouble = Double(config.percentageSold),
                  let markupDouble = Double(config.markup) else {
                continue
            }
            
            let stakePercentage = percentageSoldDouble / 100.0 // Convert percentage to decimal
            let stakeAmount = sessionStore.liveSession.buyIn * stakePercentage
            let stakeData: [String: Any]
            
            if config.isManualEntry {
                // Manual staker
                let stakerDisplayName = config.selectedManualStaker?.name ?? config.manualStakerName
                let stakerId = config.selectedManualStaker?.id ?? UUID().uuidString
                
                stakeData = [
                    "stakeAmount": stakeAmount,
                    "stakePercentage": stakePercentage,
                    "markup": markupDouble,
                    "stakedPlayerUserId": userId,
                    "stakerUserId": stakerId,
                    "gameName": sessionStore.liveSession.gameName,
                    "stakes": sessionStore.liveSession.stakes,
                    "startDateTime": Timestamp(date: sessionStore.liveSession.startTime),
                    "liveSessionId": sessionStore.liveSession.id,
                    "isOffAppStake": true,
                    "manualStakerDisplayName": stakerDisplayName,
                    "createdAt": FieldValue.serverTimestamp()
                ]
            } else {
                // App user staker
                guard let selectedStaker = config.selectedStaker else { continue }
                
                stakeData = [
                    "stakeAmount": stakeAmount,
                    "stakePercentage": stakePercentage,
                    "markup": markupDouble,
                    "stakedPlayerUserId": userId,
                    "stakerUserId": selectedStaker.id,
                    "gameName": sessionStore.liveSession.gameName,
                    "stakes": sessionStore.liveSession.stakes,
                    "startDateTime": Timestamp(date: sessionStore.liveSession.startTime),
                    "liveSessionId": sessionStore.liveSession.id,
                    "isOffAppStake": false,
                    "createdAt": FieldValue.serverTimestamp()
                ]
            }
            
            do {
                if let originalStakeId = config.originalStakeId, !originalStakeId.isEmpty {
                    // Update existing stake with merge to preserve existing fields
                    try await Firestore.firestore().collection("stakes").document(originalStakeId).setData(stakeData, merge: true)
                    print("[EnhancedLiveSessionView] Updated existing stake: \(originalStakeId)")
                } else {
                    // Create new stake
                    let docRef = try await Firestore.firestore().collection("stakes").addDocument(data: stakeData)
                    print("[EnhancedLiveSessionView] Created new stake: \(docRef.documentID)")
                    
                    // Update the config with the new stake ID for future updates
                    if let index = stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                        await MainActor.run {
                            stakerConfigs[index].originalStakeId = docRef.documentID
                            stakerConfigsForPopup[index].originalStakeId = docRef.documentID
                        }
                    }
                }
            } catch {
                print("[EnhancedLiveSessionView] Error saving stake: \(error)")
            }
        }
        
        print("[EnhancedLiveSessionView] Finished saving stakes for pause")
    }
    
    // MARK: - Helper Functions
    
    // Staking Information Section
    private var stakingInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Staking Information")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                HStack(spacing: 8) {
                                            // Add Staker Button
                    Button(action: {
                        // Prepare the copy for the popup
                        // If stakerConfigs is empty and existingStakes has items, populate from existing first.
                        if stakerConfigs.isEmpty && !existingStakes.isEmpty {
                            self.stakerConfigs = existingStakes.compactMap { stake -> StakerConfig? in
                                guard stake.stakedPlayerUserId == self.userId else { return nil }
                                var config = StakerConfig()
                                config.markup = String(stake.markup)
                                config.percentageSold = String(stake.stakePercentage * 100)
                                config.isManualEntry = stake.isOffAppStake ?? false
                                
                                if stake.isOffAppStake ?? false {
                                    // Manual staker - try to load profile asynchronously
                                    Task {
                                        do {
                                            let manualStakerProfile = try await manualStakerService.getManualStaker(id: stake.stakerUserId)
                                            await MainActor.run {
                                                if let index = self.stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                                                    self.stakerConfigs[index].selectedManualStaker = manualStakerProfile
                                                }
                                            }
                                        } catch {
                                            // Fall back to legacy display name
                                            await MainActor.run {
                                                if let index = self.stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                                                    self.stakerConfigs[index].manualStakerName = stake.manualStakerDisplayName ?? "Unknown Manual Staker"
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    // App user staker
                                    if let stakerProfile = self.userService.loadedUsers[stake.stakerUserId] {
                                        config.selectedStaker = stakerProfile
                                    } else {
                                        // Pre-fetch user for on-app stakes if not already loaded
                                        Task { await self.userService.fetchUser(id: stake.stakerUserId) }
                                    }
                                }
                                return config
                            }
                        }
                        // If still empty, add a default new one
                        if stakerConfigs.isEmpty {
                            stakerConfigs.append(StakerConfig())
                        }
                        stakerConfigsForPopup = stakerConfigs.map { config in
                            var newConfig = config
                            // Ensure originalStakeUserId is preserved during copy
                            return newConfig
                        }
                        print("[EnhancedLiveSessionView] Add Staker tapped. Copied \(stakerConfigs.count) items to stakerConfigsForPopup.")
                        showingStakingPopup = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                            Text("Add")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(6)
                    }
                    
                    // Edit Button
                    Button(action: {
                        // Prepare the copy for the popup
                        // If stakerConfigs is empty and existingStakes has items, populate from existing first.
                        if stakerConfigs.isEmpty && !existingStakes.isEmpty {
                            self.stakerConfigs = existingStakes.compactMap { stake -> StakerConfig? in
                                guard stake.stakedPlayerUserId == self.userId else { return nil }
                                var config = StakerConfig()
                                config.markup = String(stake.markup)
                                config.percentageSold = String(stake.stakePercentage * 100)
                                config.isManualEntry = stake.isOffAppStake ?? false
                                
                                if stake.isOffAppStake ?? false {
                                    // Manual staker - try to load profile asynchronously
                                    Task {
                                        do {
                                            let manualStakerProfile = try await manualStakerService.getManualStaker(id: stake.stakerUserId)
                                            await MainActor.run {
                                                if let index = self.stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                                                    self.stakerConfigs[index].selectedManualStaker = manualStakerProfile
                                                }
                                            }
                                        } catch {
                                            // Fall back to legacy display name
                                            await MainActor.run {
                                                if let index = self.stakerConfigs.firstIndex(where: { $0.id == config.id }) {
                                                    self.stakerConfigs[index].manualStakerName = stake.manualStakerDisplayName ?? "Unknown Manual Staker"
                                                }
                                            }
                                        }
                                    }
                                } else {
                                    // App user staker
                                    if let stakerProfile = self.userService.loadedUsers[stake.stakerUserId] {
                                        config.selectedStaker = stakerProfile
                                    } else {
                                        // Pre-fetch user for on-app stakes if not already loaded
                                        Task { await self.userService.fetchUser(id: stake.stakerUserId) }
                                    }
                                }
                                return config
                            }
                        }
                        // If still empty (e.g. no existing stakes), ensure at least one config for popup
                         if stakerConfigs.isEmpty {
                            stakerConfigs.append(StakerConfig())
                        }
                        stakerConfigsForPopup = stakerConfigs.map { config in
                            var newConfig = config
                            // Ensure originalStakeUserId is preserved during copy
                            return newConfig
                        }
                        print("[EnhancedLiveSessionView] Edit Stakes tapped. Copied \(stakerConfigs.count) items to stakerConfigsForPopup.")
                        showingStakingPopup = true
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
            
            if isLoadingStakes {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    Text("Loading staking info...")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
            } else if !existingStakes.isEmpty || !validStakerConfigs.isEmpty {
                VStack(spacing: 12) {
                    // Show existing stakes first
                    ForEach(existingStakes.filter { $0.stakedPlayerUserId == userId }, id: \.id) { stake in
                        StakingInfoCard(stake: stake, userService: userService)
                    }
                    
                    // Show configured stakers (that aren't already saved as stakes)
                    ForEach(validStakerConfigs, id: \.id) { config in
                        StakingConfigCard(config: getRestoreStakerConfig(config))
                    }
                }
            }
        }
        .padding(16)
        .glassyBackground(cornerRadius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Helper Functions
    
    // Staking Info Card for existing stakes
    private struct StakingInfoCard: View {
        let stake: Stake
        @ObservedObject var userService: UserService
        @State private var manualStakerProfile: ManualStakerProfile? = nil
        @State private var isLoadingManualStaker = false
        
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if stake.isOffAppStake ?? false {
                        // Manual staker
                        if let profile = manualStakerProfile {
                            Text(profile.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        } else if isLoadingManualStaker {
                            Text("Loading manual staker...")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            Text(stake.manualStakerDisplayName ?? "Manual Staker")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    } else {
                        // App user staker
                        if let stakerProfile = userService.loadedUsers[stake.stakerUserId] {
                            Text("\(stakerProfile.displayName ?? stakerProfile.username)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        } else {
                            Text("Loading staker...")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Text("\(Int(stake.stakePercentage * 100))% at \(stake.markup, specifier: "%.2f")x markup")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    
                    Text(stake.status.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(stake.status == .settled ? .green : .orange)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassyBackground(cornerRadius: 10, materialOpacity: 0.1, glassOpacity: 0.05)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .onAppear {
                if stake.isOffAppStake ?? false {
                    loadManualStakerProfile()
                }
            }
        }
        
        private func loadManualStakerProfile() {
            guard manualStakerProfile == nil && !isLoadingManualStaker else { return }
            
            isLoadingManualStaker = true
            Task {
                do {
                    let manualStakerService = ManualStakerService()
                    let profile = try await manualStakerService.getManualStaker(id: stake.stakerUserId)
                    await MainActor.run {
                        self.manualStakerProfile = profile
                        self.isLoadingManualStaker = false
                    }
                } catch {
                    await MainActor.run {
                        self.isLoadingManualStaker = false
                        print("Error loading manual staker profile: \(error)")
                    }
                }
            }
        }
    }
    
    // Staking Config Card for new/editing configs
    private struct StakingConfigCard: View {
        let config: StakerConfig
        
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if config.isManualEntry {
                        Text(config.selectedManualStaker?.name ?? (config.manualStakerName.isEmpty ? "Manual Staker" : config.manualStakerName))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    } else {
                        Text(config.selectedStaker?.displayName ?? config.selectedStaker?.username ?? "Loading...")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    Text("\(config.percentageSold)% at \(config.markup)x markup")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Status")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    
                    Text("Configured")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassyBackground(cornerRadius: 10, materialOpacity: 0.1, glassOpacity: 0.05)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.blue.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
    

    
    // MARK: - Edit Session Sheet
    
    private var editSessionSheet: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()
                        .onTapGesture {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Header
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Edit Session Details")
                                    .font(.plusJakarta(.title2, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Modify session information and staking configuration")
                                    .font(.plusJakarta(.subheadline))
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            
                            // Session Start Time Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Session Start Time")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                                
                                DatePicker(
                                    "Start Time",
                                    selection: $editSessionStartTime,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                .datePickerStyle(.compact)
                                .colorScheme(.dark)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Material.ultraThinMaterial)
                                        .opacity(0.2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            .padding(.horizontal)
                            
                            // Game Details Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Game Details")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                                
                                GlassyInputField(
                                    icon: "gamecontroller",
                                    title: "Game Name",
                                    content: AnyGlassyContent(TextFieldContent(
                                        text: $editGameName,
                                        textColor: .white
                                    )),
                                    glassOpacity: 0.01,
                                    labelColor: .gray,
                                    materialOpacity: 0.2
                                )
                                
                                GlassyInputField(
                                    icon: "dollarsign.circle",
                                    title: "Stakes",
                                    content: AnyGlassyContent(TextFieldContent(
                                        text: $editStakes,
                                        textColor: .white
                                    )),
                                    glassOpacity: 0.01,
                                    labelColor: .gray,
                                    materialOpacity: 0.2
                                )
                            }
                            .padding(.horizontal)
                            
                            // Staking Configuration Section
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Text("Staking Configuration")
                                        .font(.plusJakarta(.headline, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    HStack(spacing: 8) {
                                        // Add New Staker Button
                                        Button(action: {
                                            stakerConfigs.append(StakerConfig())
                                            showingStakingPopup = true
                                        }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus.circle.fill")
                                                    .font(.system(size: 12))
                                                Text("Add Staker")
                                            }
                                            .font(.plusJakarta(.caption, weight: .semibold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.green.opacity(0.2))
                                            .cornerRadius(8)
                                        }
                                        
                                        // Edit Existing Stakes Button
                                        if !stakerConfigs.isEmpty || !existingStakes.isEmpty {
                                            Button(action: {
                                                if stakerConfigs.isEmpty {
                                                    stakerConfigs.append(StakerConfig())
                                                }
                                                showingStakingPopup = true
                                            }) {
                                                Text("Edit Stakes")
                                                    .font(.plusJakarta(.caption, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.9))
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(Color.white.opacity(0.1))
                                                    .cornerRadius(8)
                                            }
                                        }
                                    }
                                }
                                .padding(.leading, 6)
                                
                                if stakerConfigs.isEmpty && existingStakes.isEmpty {
                                    Text("No staking configuration set")
                                        .font(.plusJakarta(.subheadline))
                                        .foregroundColor(.gray)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                } else {
                                    VStack(spacing: 12) {
                                        // Show existing stakes
                                        ForEach(existingStakes.filter { $0.stakedPlayerUserId == userId }, id: \.id) { stake in
                                            StakingInfoCard(stake: stake, userService: userService)
                                        }
                                        
                                        // Show configured stakes
                                        ForEach(stakerConfigs, id: \.id) { config in
                                            if let staker = config.selectedStaker,
                                               !config.percentageSold.isEmpty,
                                               !config.markup.isEmpty {
                                                StakingConfigCard(config: config)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                            
                                        // Save Button
            Button(action: saveSessionChanges) {
                Text("Save Changes")
                    .font(.plusJakarta(.body, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white)
                    )
            }
            .padding(.horizontal)
            
            // Discard Session Button
            Button(action: {
                showingDiscardSessionAlert = true
            }) {
                Text("Discard Session")
                    .font(.plusJakarta(.body, weight: .bold))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.red, lineWidth: 2)
                            .background(Color.clear)
                    )
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
                        }
                        .padding(.top, 20)
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showingEditSessionSheet = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .overlay(
            // Add floating staking popup overlay specifically to the edit session sheet
            FloatingStakingPopup(
                isPresented: $showingStakingPopup,
                stakerConfigs: $stakerConfigsForPopup, // Pass the copy here
                userService: userService,
                manualStakerService: manualStakerService,
                userId: userId,
                primaryTextColor: .white,
                secondaryTextColor: Color.white.opacity(0.7),
                glassOpacity: 0.01,
                materialOpacity: 0.2
            )
        )
        .alert("Discard Session?", isPresented: $showingDiscardSessionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                discardSession()
            }
        } message: {
            Text("This will delete your current session permanently. All session data, notes, and hand histories will be lost.")
        }
    }
    
    // MARK: - Save Session Changes
    
    private func saveSessionChanges() {
        // Update session store with new values
        sessionStore.liveSession.startTime = editSessionStartTime
        sessionStore.liveSession.gameName = editGameName
        sessionStore.liveSession.stakes = editStakes
        
        // Recalculate elapsed time based on new start time
        if sessionStore.liveSession.isActive {
            sessionStore.liveSession.elapsedTime = Date().timeIntervalSince(editSessionStartTime)
        } else if let lastPausedAt = sessionStore.liveSession.lastPausedAt {
            sessionStore.liveSession.elapsedTime = lastPausedAt.timeIntervalSince(editSessionStartTime)
        }
        
        // Save the updated session state
        sessionStore.saveLiveSessionState()
        
        // Close the edit sheet
        showingEditSessionSheet = false
    }
    
    // MARK: - Discard Session
    
    private func discardSession() {
        // Clear the live session from the store
        sessionStore.endAndClearLiveSession()
        
        // Close the edit sheet first
        showingEditSessionSheet = false
        
        // Then dismiss the entire session view
        dismiss()
    }
    
    // MARK: - Live Session Challenge Section
    
    private var liveSessionChallengeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Challenges")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            let sessionChallenges = challengeService.activeChallenges.filter { $0.type == .session }
            
            ForEach(sessionChallenges) { challenge in
                LiveSessionChallengeCard(
                    challenge: challenge,
                    currentSessionHours: sessionStore.liveSession.elapsedTime / 3600.0,
                    sessionStartTime: sessionStore.liveSession.startTime
                )
            }
        }
        .padding(16)
        .glassyBackground(cornerRadius: 16)
    }
    
    // MARK: - Live Session Challenge Card
    
    private struct LiveSessionChallengeCard: View {
        let challenge: Challenge
        let currentSessionHours: Double
        let sessionStartTime: Date
        
        private var sessionQualifies: Bool {
            if let minHours = challenge.minHoursPerSession {
                return currentSessionHours >= minHours
            }
            return true
        }
        
        private var projectedProgress: String {
            if let targetCount = challenge.targetSessionCount {
                let currentValidSessions = challenge.validSessionsCount + (sessionQualifies ? 1 : 0)
                return "\(currentValidSessions)/\(targetCount)"
            } else if let targetHours = challenge.targetHours {
                let projectedTotalHours = challenge.totalHoursPlayed + currentSessionHours
                return "\(String(format: "%.1f", projectedTotalHours))/\(String(format: "%.1f", targetHours))h"
            }
            return ""
        }
        
        private var wouldComplete: Bool {
            if let targetCount = challenge.targetSessionCount {
                let currentValidSessions = challenge.validSessionsCount + (sessionQualifies ? 1 : 0)
                return currentValidSessions >= targetCount
            } else if let targetHours = challenge.targetHours {
                let projectedTotalHours = challenge.totalHoursPlayed + currentSessionHours
                return projectedTotalHours >= targetHours
            }
            return false
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(challenge.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if wouldComplete {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.green)
                            
                            Text("Will Complete!")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.green)
                        }
                    } else {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Current Session")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                            
                            Text("\(String(format: "%.1f", currentSessionHours))h")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("After Session")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.gray)
                            
                            Text(projectedProgress)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(wouldComplete ? .green : .orange)
                        }
                    }
                    
                    if let minHours = challenge.minHoursPerSession {
                        HStack(spacing: 4) {
                            Image(systemName: sessionQualifies ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(sessionQualifies ? .green : .gray)
                            
                            Text("Minimum \(String(format: "%.1f", minHours))h required")
                                .font(.system(size: 12))
                                .foregroundColor(sessionQualifies ? .green : .gray)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(wouldComplete ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(wouldComplete ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Helper Functions
    
    // Combine chip updates that occur within a specified time window (in seconds)
    private func combineChipUpdatesWithinTimeWindow(_ updates: [ChipStackUpdate], timeWindow: TimeInterval) -> [ChipStackUpdate] {
        guard !updates.isEmpty else { return [] }
        
        // Sort updates by timestamp to ensure proper ordering
        let sortedUpdates = updates.sorted { $0.timestamp < $1.timestamp }
        var combinedUpdates: [ChipStackUpdate] = []
        var currentGroup: [ChipStackUpdate] = []
        
        for update in sortedUpdates {
            if let lastInGroup = currentGroup.last {
                // Check if this update is within the time window of the last update in the current group
                if update.timestamp.timeIntervalSince(lastInGroup.timestamp) <= timeWindow {
                    // Add to current group
                    currentGroup.append(update)
                } else {
                    // Time window exceeded, finalize current group and start new one
                    if let combinedUpdate = combineGroupOfUpdates(currentGroup) {
                        combinedUpdates.append(combinedUpdate)
                    }
                    currentGroup = [update]
                }
            } else {
                // First update in group
                currentGroup = [update]
            }
        }
        
        // Don't forget to process the last group
        if let combinedUpdate = combineGroupOfUpdates(currentGroup) {
            combinedUpdates.append(combinedUpdate)
        }
        
        return combinedUpdates
    }
    
    // Combine a group of chip updates into a single update
    private func combineGroupOfUpdates(_ group: [ChipStackUpdate]) -> ChipStackUpdate? {
        guard !group.isEmpty else { return nil }
        
        // If only one update in group, return it as-is
        if group.count == 1 {
            return group.first
        }
        
        // Combine multiple updates
        let firstUpdate = group.first!
        let lastUpdate = group.last!
        
        // Use the most recent timestamp
        let timestamp = lastUpdate.timestamp
        
        // Use the final amount from the last update
        let amount = lastUpdate.amount
        
        // Combine notes meaningfully, focusing on showing the sum
        let notes = group.compactMap { $0.note }.filter { !$0.isEmpty }
        let combinedNote: String?
        
        // Check if all notes are "Quick add/subtract" type to create a meaningful summary
        let quickAddNotes = notes.filter { note in
            note.lowercased().contains("quick add") || note.lowercased().contains("quick subtract")
        }
        
        if quickAddNotes.count == notes.count && !quickAddNotes.isEmpty {
            // All are quick updates - calculate the sum of all individual changes
            var totalChange: Double = 0
            for note in quickAddNotes {
                // Extract the amount from notes like "Quick add: +$5" or "Quick subtract: -$25"
                let components = note.components(separatedBy: "$")
                if components.count > 1 {
                    let amountString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if let changeAmount = Double(amountString) {
                        if note.lowercased().contains("subtract") {
                            totalChange -= changeAmount
                        } else {
                            totalChange += changeAmount
                        }
                    }
                }
            }
            
            let changeText = totalChange >= 0 ? "+$\(Int(totalChange))" : "$\(Int(totalChange))"
            combinedNote = "Quick add: \(changeText)"
        } else if notes.isEmpty {
            // Calculate net change from first to last for non-quick updates
            let totalChange = lastUpdate.amount - firstUpdate.amount
            let changeText = totalChange >= 0 ? "+$\(Int(totalChange))" : "-$\(Int(abs(totalChange)))"
            combinedNote = "Combined \(group.count) updates (\(changeText))"
        } else if notes.count == 1 {
            combinedNote = notes.first
        } else {
            // If multiple different notes, show a summary with total change
            let uniqueNotes = Array(Set(notes))
            if uniqueNotes.count == 1 {
                combinedNote = uniqueNotes.first
            } else {
                let totalChange = lastUpdate.amount - firstUpdate.amount
                let changeText = totalChange >= 0 ? "+$\(Int(totalChange))" : "-$\(Int(abs(totalChange)))"
                combinedNote = "Combined \(group.count) updates (\(changeText)): \(uniqueNotes.joined(separator: "; "))"
            }
        }
        
        // Create combined update with a new ID that represents the combination
        let combinedId = group.map { $0.id }.joined(separator: "_")
        
        return ChipStackUpdate(
            id: combinedId,
            amount: amount,
            note: combinedNote,
            timestamp: timestamp
        )
    }
    
    // Function to restore missing staker profiles when they get lost
    private func restoreMissingStakerProfiles() {
        for (index, config) in stakerConfigs.enumerated() {
            if !config.isManualEntry && config.selectedStaker == nil {
                if let originalUserId = config.originalStakeUserId,
                   let existingProfile = userService.loadedUsers[originalUserId] {
                    print("[EnhancedLiveSessionView] Restoring missing staker profile at index \(index): \(existingProfile.username)")
                    stakerConfigs[index].selectedStaker = existingProfile
                    
                    // Also update popup copy if it exists
                    if index < stakerConfigsForPopup.count {
                        stakerConfigsForPopup[index].selectedStaker = existingProfile
                    }
                }
            }
        }
    }
    
    // Function to get a config with restored staker profile if needed
    private func getRestoreStakerConfig(_ config: StakerConfig) -> StakerConfig {
        var restoredConfig = config
        if !config.isManualEntry && config.selectedStaker == nil {
            if let originalUserId = config.originalStakeUserId,
               let existingProfile = userService.loadedUsers[originalUserId] {
                restoredConfig.selectedStaker = existingProfile
            }
        }
        return restoredConfig
    }
    
    // Load and populate staker configuration from accepted event staking invites
    private func loadEventStakingInvites(for event: Event) async {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return }
        
        do {
            // Fetch accepted stakes for this event where current user is the player
            let allStakes = try await stakeService.fetchStakes(forUser: currentUserId)
            print("[EnhancedLiveSessionView] Total stakes fetched: \(allStakes.count)")
            
            // Debug all stakes first
            for (index, stake) in allStakes.enumerated() {
                print("[EnhancedLiveSessionView] Stake \(index): sessionGameName='\(stake.sessionGameName)', status=\(stake.status), stakedPlayerUserId=\(stake.stakedPlayerUserId), totalBuyIn=\(stake.totalPlayerBuyInForSession), cashout=\(stake.playerCashoutForSession), isOffAppStake=\(stake.isOffAppStake ?? false), manualDisplayName='\(stake.manualStakerDisplayName ?? "nil")', stakerUserId='\(stake.stakerUserId)'")
            }
            
            // Count by type for debugging
            let manualStakes = allStakes.filter { $0.isOffAppStake == true }
            let appStakes = allStakes.filter { $0.isOffAppStake != true }
            print("[EnhancedLiveSessionView] Total stakes breakdown: \(manualStakes.count) manual, \(appStakes.count) app stakers")
            
            let acceptedStakes = allStakes.filter { stake in
                    // Filter for stakes that:
                    // 1. Are active (accepted from event invite)
                    // 2. Have event name matching
                    // 3. User is the staked player
                    // 4. Haven't started yet (no buy-in/cashout data)
                    let statusMatch = stake.status == .active
                    let nameMatch = stake.sessionGameName == event.event_name
                    let playerMatch = stake.stakedPlayerUserId == currentUserId
                    let notStartedMatch = stake.totalPlayerBuyInForSession == 0 && stake.playerCashoutForSession == 0
                    
                    let matches = statusMatch && nameMatch && playerMatch && notStartedMatch
                    
                    print("[EnhancedLiveSessionView] Checking stake: statusMatch=\(statusMatch), nameMatch=\(nameMatch), playerMatch=\(playerMatch), notStartedMatch=\(notStartedMatch), finalMatch=\(matches)")
                    
                    if matches {
                        print("[EnhancedLiveSessionView] Found matching stake: \(stake.manualStakerDisplayName ?? "app user"), isOffAppStake: \(stake.isOffAppStake ?? false)")
                    }
                    return matches
                }
            
            print("[EnhancedLiveSessionView] Filtered stakes for event '\(event.event_name)': \(acceptedStakes.count)")
            
            // Deduplicate stakes by unique identifier - for app users use stakerUserId, for manual stakers use stake ID
            var deduplicatedStakes: [Stake] = []
            var seenStakerKeys: Set<String> = []
            
            // Sort by date descending (most recent first) to keep the latest stake for each staker
            let sortedStakes = acceptedStakes.sorted { $0.proposedAt > $1.proposedAt }
            
            for stake in sortedStakes {
                // Create unique key for each staker
                let stakerKey: String
                if stake.isOffAppStake == true {
                    // For manual stakers, use stake ID as unique key since they might share the same placeholder stakerUserId
                    stakerKey = "manual_\(stake.id ?? UUID().uuidString)"
                } else {
                    // For app users, use stakerUserId as key
                    stakerKey = "app_\(stake.stakerUserId)"
                }
                
                if !seenStakerKeys.contains(stakerKey) {
                    deduplicatedStakes.append(stake)
                    seenStakerKeys.insert(stakerKey)
                    print("[EnhancedLiveSessionView] Keeping stake for staker key: \(stakerKey), ID: \(stake.id ?? "nil")")
                } else {
                    print("[EnhancedLiveSessionView] Skipping duplicate stake for staker key: \(stakerKey), ID: \(stake.id ?? "nil")")
                }
            }
            
            print("[EnhancedLiveSessionView] After deduplication: \(deduplicatedStakes.count) unique stakers")
            
            await MainActor.run {
                // Convert stakes to StakerConfig objects
                self.stakerConfigs = deduplicatedStakes.compactMap { stake -> StakerConfig? in
                    var config = StakerConfig()
                    config.markup = String(stake.markup)
                    config.percentageSold = String(stake.stakePercentage * 100)
                    config.isManualEntry = stake.isOffAppStake ?? false
                    
                    // Store the original stake user ID for reference
                    config.originalStakeUserId = stake.stakerUserId
                    
                    // Store the original stake ID so we can update it instead of creating a new one
                    config.originalStakeId = stake.id
                    
                    if stake.isOffAppStake ?? false {
                        // Manual staker
                        config.manualStakerName = stake.manualStakerDisplayName ?? "Manual Staker"
                        // Try to load manual staker profile asynchronously but safely
                        let configId = config.id // Capture the config ID
                        let stakerUserId = stake.stakerUserId // Capture the staker user ID
                        Task { @MainActor in
                            do {
                                // Ensure the stakerUserId is valid before attempting to fetch
                                guard !stakerUserId.isEmpty else {
                                    print("[EnhancedLiveSessionView] Invalid stakerUserId for manual staker")
                                    return
                                }
                                let manualStakerProfile = try await manualStakerService.getManualStaker(id: stakerUserId)
                                // Find the config again by ID to ensure it still exists
                                if let index = self.stakerConfigs.firstIndex(where: { $0.id == configId }) {
                                    self.stakerConfigs[index].selectedManualStaker = manualStakerProfile
                                    // Also update popup copy if it exists
                                    if let popupIndex = self.stakerConfigsForPopup.firstIndex(where: { $0.id == configId }) {
                                        self.stakerConfigsForPopup[popupIndex].selectedManualStaker = manualStakerProfile
                                    }
                                }
                            } catch {
                                print("[EnhancedLiveSessionView] Failed to load manual staker profile for ID '\(stakerUserId)': \(error)")
                            }
                        }
                    } else {
                        // App user staker - load synchronously first, then async if needed
                        if let existingProfile = userService.loadedUsers[stake.stakerUserId] {
                            config.selectedStaker = existingProfile
                            print("[EnhancedLiveSessionView] Found existing profile for \(existingProfile.username)")
                        } else {
                            print("[EnhancedLiveSessionView] Need to load profile for user ID: \(stake.stakerUserId)")
                            // Load asynchronously but ensure it gets assigned safely
                            let configId = config.id // Capture the config ID
                            let stakerUserId = stake.stakerUserId // Capture the staker user ID
                            Task { @MainActor in
                                await userService.fetchUser(id: stakerUserId)
                                if let stakerProfile = self.userService.loadedUsers[stakerUserId] {
                                    print("[EnhancedLiveSessionView] Loaded profile: \(stakerProfile.username)")
                                    // Find the config again by ID to ensure it still exists
                                    if let index = self.stakerConfigs.firstIndex(where: { $0.id == configId }) {
                                        self.stakerConfigs[index].selectedStaker = stakerProfile
                                        // Update the popup copy as well if it exists
                                        if let popupIndex = self.stakerConfigsForPopup.firstIndex(where: { $0.id == configId }) {
                                            self.stakerConfigsForPopup[popupIndex].selectedStaker = stakerProfile
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    return config
                }
                
                // Update the popup copy as well
                self.stakerConfigsForPopup = self.stakerConfigs
                
                // Auto-restore any missing staker profiles
                self.restoreMissingStakerProfiles()
                
                print("[EnhancedLiveSessionView] Loaded \(self.stakerConfigs.count) stakers from event invites for event: \(event.event_name)")
                
                // Show a temporary visual indicator if stakes were loaded
                if !self.stakerConfigs.isEmpty {
                    // This will help you see if stakes are being loaded properly
                    print("[EnhancedLiveSessionView] ✅ SUCCESS: Loaded \(self.stakerConfigs.count) staker configurations")
                    for (index, config) in self.stakerConfigs.enumerated() {
                        print("[EnhancedLiveSessionView] Staker \(index + 1): isManual=\(config.isManualEntry), percentage=\(config.percentageSold)%, markup=\(config.markup)x")
                    }
                } else {
                    print("[EnhancedLiveSessionView] ⚠️ WARNING: No staker configurations loaded for event \(event.event_name)")
                }
            }
        } catch {
            print("[EnhancedLiveSessionView] Failed to load event staking invites: \(error)")
        }
    }
    
    // MARK: - Session Result Share View
    
    private var sessionResultShareView: some View {
        SessionResultShareView(
            sessionDetails: sessionDetails,
            isTournament: isTournamentSession,
            onShareToFeed: {
                // Switch to post editor state within the sharing flow
                sharingFlowState = .postEditor
            },
            onShareToSocials: {
                sharingFlowState = .imagePicker
            },
            onDone: {
                sharingFlowState = .none
                dismiss()
            }
        )
    }
}

// Wrapper view to handle PostEditor callbacks
private struct SessionPostEditorWrapper: View {
    let userId: String
    let completedSession: Session
    let onSuccess: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var sessionStore: SessionStore
    
    var body: some View {
        PostEditorView(
            userId: userId,
            completedSession: completedSession,
            onCancel: onCancel
        )
        .environmentObject(postService)
        .environmentObject(userService)
        .environmentObject(sessionStore)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PostCreatedSuccessfully"))) { _ in
            onSuccess()
        }
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


// View for editing an existing note
struct EditNoteView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionStore: SessionStore
    let noteIndex: Int
    @State private var editText: String

    init(sessionStore: SessionStore, noteIndex: Int, initialText: String) {
        self.sessionStore = sessionStore
        self.noteIndex = noteIndex
        _editText = State(initialValue: initialText)
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in // Wrap in GeometryReader
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        TextEditor(text: $editText)
                            // Set a specific height, e.g., 1/3 of the available height or a fixed value
                            .frame(height: geometry.size.height * 0.35) 
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Material.ultraThinMaterial)
                                    .opacity(0.2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .foregroundColor(.white)
                            .accentColor(.white) // Cursor color
                            .scrollContentBackground(.hidden) // To make TextEditor background transparent on iOS 16+
                            .padding(.horizontal)

                        Button(action: {
                            sessionStore.updateNote(at: noteIndex, with: editText)
                            dismiss()
                        }) {
                            Text("Save Note")
                                .font(.plusJakarta(.body, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.white)
                                )
                        }
                        .padding(.horizontal)
                        
                        Spacer() // Pushes content to the top
                    }
                    .padding(.top, 20)
                }
                .navigationTitle("Edit Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    }
                }
                .onTapGesture {
                     UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                // Remove keyboard safe area handling - REMOVED
                // .ignoresSafeArea(.keyboard)
            }
        }
    }
}

// MARK: - Glassy Background Modifier
private struct GlassyBackground: ViewModifier {
    var cornerRadius: CGFloat = 16
    var materialOpacity: Double = 0.2
    var glassOpacity: Double = 0.01

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Material.ultraThinMaterial)
                        .opacity(materialOpacity)
                    
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(glassOpacity))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func glassyBackground(cornerRadius: CGFloat = 16, materialOpacity: Double = 0.2, glassOpacity: Double = 0.01) -> some View {
        self.modifier(GlassyBackground(cornerRadius: cornerRadius, materialOpacity: materialOpacity, glassOpacity: glassOpacity))
    }
}



