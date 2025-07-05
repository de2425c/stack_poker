import SwiftUI
import FirebaseAuth
import PhotosUI
import Combine
import Foundation
import FirebaseStorage
import FirebaseFirestore
import Kingfisher

// Wrapper for image URL to make it Identifiable for GroupChatView
struct GroupImageURL: Identifiable {
    let id = UUID()
    let url: String
}

// Add print statements for key lifecycle events
extension View {
    func onViewLifecycle(created: String? = nil, appeared: String? = nil, disappeared: String? = nil) -> some View {
        self
            .onAppear {
                if let msg = appeared {
                    let timestamp = Date()

                }
            }
            .onDisappear {
                if let msg = disappeared {
                    let timestamp = Date()

                }
            }
            .task {
                if let msg = created {
                    let timestamp = Date()

                }
            }
    }
}

struct GroupChatView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var groupService = GroupService()
    private let homeGameService = HomeGameService()
    // REMOVED: @EnvironmentObject private var handStore: HandStore
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityManager
    
    // State for messages that we manually update from the subscription
    @State private var messageText = ""
    @State private var showingImagePicker = false
    // REMOVED: @State private var showingHandPicker = false
    @State private var showingHomeGameView = false
    @State private var selectedImage: UIImage?
    @State private var imagePickerItem: PhotosPickerItem?
    @State private var isLoadingMessages = false
    @State private var isSendingMessage = false
    @State private var isSendingImage = false
    @State private var error: String?
    @State private var showError = false
    @State private var viewState: ViewState = .loading
    
    // Add pagination state
    @State private var isLoadingMoreMessages = false
    @State private var hasMoreMessages = true
    @State private var lastLoadedCount = 0
    @State private var shouldAutoScroll = true // Track if we should auto-scroll
    
    // Add FocusState for the text field
    @FocusState private var isTextFieldFocused: Bool
    
    // For scrolling to bottom
    @State private var scrollToBottom = false
    @State private var lastMessageId: String?
    
    // To store cancellables
    @State private var cancellables = Set<AnyCancellable>()
    
    // Debug timestamps
    @State private var viewCreatedTime = Date()
    @State private var renderStartTime = Date()
    @State private var renderEndTime = Date()
    
    @State var group: UserGroup
    
    // Add pinnedHomeGame state
    @State private var pinnedHomeGame: HomeGame?
    @State private var isPinnedGameLoading = false
    
    // Enhanced keyboard tracking properties
    @State private var keyboardHeight: CGFloat = 0
    @State private var isKeyboardVisible = false
    @State private var keyboardAnimationDuration: Double = 0.25
    
    // Add dynamic text input height tracking
    @State private var textInputHeight: CGFloat = 44 // Starting height
    private let minInputHeight: CGFloat = 44
    private let maxInputHeight: CGFloat = 140 // Increased for more text space
    
    // Enum to track view state
    enum ViewState: Equatable {
        case loading
        case ready
        case error(String)
        
        static func == (lhs: ViewState, rhs: ViewState) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.ready, .ready):
                return true
            case (.error(let lhsMessage), .error(let rhsMessage)):
                return lhsMessage == rhsMessage
            default:
                return false
            }
        }
    }
    
    @State private var isShowingGroupDetail = false
    
    // Global image viewer state for full-screen images
    @State private var viewerImageURL: GroupImageURL? = nil
    
    init(group: UserGroup) {
        _group = State(initialValue: group)
    }
    
    // MARK: - Navigation Bar
    private var navigationBar: some View {
        HStack {
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color(red: 30/255, green: 33/255, blue: 36/255).opacity(0.8)))
            }
            
            Spacer()
            
            Text(group.name)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            Spacer()
            
            Button(action: { isShowingGroupDetail = true }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Circle().fill(Color(red: 30/255, green: 33/255, blue: 36/255).opacity(0.8)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Pinned Game View
    @ViewBuilder
    private var pinnedGameView: some View {
        if isPinnedGameLoading {
            HStack {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                
                Text("Loading active game...")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .padding(.leading, 8)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 25/255, green: 27/255, blue: 32/255).opacity(0.8))
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
        } else if let pinnedGame = pinnedHomeGame {
            NavigationLink(destination: HomeGameDetailView(game: pinnedGame)
                .environmentObject(sessionStore)) {
                HStack {
                    // Game icon
                    ZStack {
                        Circle()
                            .fill(Color(UIColor(red: 40/255, green: 60/255, blue: 40/255, alpha: 1.0)))
                            .frame(width: 32, height: 32)
                        
                        Image(systemName: "house.fill")
                            .font(.system(size: 16))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pinnedGame.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        
                        Text("\(pinnedGame.players.filter { $0.status == .active }.count) active players")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    Text("ACTIVE")
                        .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                            )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 25/255, green: 27/255, blue: 32/255).opacity(0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color.white.opacity(0.2),
                                            Color.white.opacity(0.05),
                                            Color.clear
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }
    
    // MARK: - Input Bar
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.gray.opacity(0.3))
            
            HStack(alignment: .center, spacing: 12) {
                // + Button with menu - centered with text input
                Menu {
                    Button(action: {
                        imagePickerItem = nil
                        showingImagePicker = true
                    }) {
                        Label("Photo", systemImage: "photo")
                    }
                    
                    // REMOVED: Hand sharing button
                    /*
                    Button(action: {
                        showingHandPicker = true
                    }) {
                        Label("Hands", systemImage: "doc.text")
                    }
                    */
                    
                    Button(action: {
                        showingHomeGameView = true
                    }) {
                        Label("Home Game", systemImage: "house")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                .frame(height: textInputHeight) // Match the text input height for proper centering
                
                // Text input field with dynamic height
                HStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                            .frame(height: textInputHeight)
                        
                        // Placeholder text - centered vertically
                        if messageText.isEmpty {
                            Text("Message")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .padding(.leading, 24)
                                .frame(height: textInputHeight)
                                .allowsHitTesting(false)
                        }
                        
                        // TextEditor for multi-line input
                        TextEditor(text: $messageText)
                            .focused($isTextFieldFocused)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                            .background(Color.clear)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(height: textInputHeight)
                            .onSubmit {
                                if !messageText.isEmpty {
                                    sendTextMessage()
                                }
                            }
                            .onChange(of: messageText) { newValue in
                                updateTextInputHeight(for: newValue)
                            }
                    }
                }
                
                // Send button - centered with text input
                if !messageText.isEmpty {
                    Button(action: sendTextMessage) {
                        Image(systemName: isSendingMessage ? "circle" : "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .overlay(
                                Group {
                                    if isSendingMessage {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                                    }
                                }
                            )
                    }
                    .frame(width: 24, height: 24)
                    .frame(height: textInputHeight) // Match the text input height for proper centering
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8) // Small bottom padding for better visual spacing
        }
        .background(Color(UIColor(red: 25/255, green: 25/255, blue: 30/255, alpha: 0.95)))
        // Move up with keyboard using proper animation
        .offset(y: -keyboardHeight + (isKeyboardVisible ? 32 : 0))
        .animation(.easeOut(duration: keyboardAnimationDuration), value: keyboardHeight)
        .animation(.easeOut(duration: 0.2), value: textInputHeight) // Smooth height animation
    }
    
    // MARK: - Message List Content
    @ViewBuilder
    private var messageListContent: some View {
        VStack(spacing: 0) {
            // Load more messages indicator at the top
            if hasMoreMessages {
                Button(action: loadMoreMessages) {
                    HStack {
                        if isLoadingMoreMessages {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.up.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Text(isLoadingMoreMessages ? "Loading messages..." : "Load more messages")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(red: 30/255, green: 33/255, blue: 36/255).opacity(0.8))
                    )
                }
                .disabled(isLoadingMoreMessages)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            
            // Removed unnecessary top spacer so messages start right under the header
            Spacer().frame(height: 0)
            
            let _ = print("🎯 MessageListContent - isLoadingMessages: \(isLoadingMessages), messages count: \(groupService.groupMessages.count)")
            
            if isLoadingMessages && groupService.groupMessages.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 100)
            } else if groupService.groupMessages.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    Text("No messages yet")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Start the conversation by sending a message")
                        .font(.system(size: 15))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 100)
            } else {
                // Group messages by sender and time (1 minute window)
                let groupedMessages = groupMessages(groupService.groupMessages)
                let _ = print("🎯 Grouped messages count: \(groupedMessages.count)")
                
                // Message groups with proper spacing
                LazyVStack(spacing: 8) {
                    ForEach(groupedMessages, id: \.id) { messageGroup in
                        MessageGroupView(messageGroup: messageGroup, onImageTapped: { url in
                            viewerImageURL = GroupImageURL(url: url)
                        })
                            .id(messageGroup.id)
                            .padding(.horizontal, 16)
                    }
                }
            }
            
            // Bottom padding for input bar + keyboard
            Spacer().frame(height: isKeyboardVisible ? keyboardHeight + 115 : 125)
            
            // Anchor for scrolling to bottom
            Color.clear.frame(height: 1)
                .id("bottomAnchor")
        }
    }
    
    // MARK: - Loading State View
    private var loadingStateView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Loading chat...")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onViewLifecycle(appeared: "Loading state")
    }
    
    // MARK: - Main Content View
    @ViewBuilder
    private var mainContentView: some View {
        let _ = print("🎯 MainContentView - viewState: \(viewState)")
        switch viewState {
        case .loading:
            loadingStateView
            
        case .ready:
            readyStateView
            
        case .error:
            errorStateView
        }
    }
    
    // MARK: - Ready State View
    private var readyStateView: some View {
        VStack(spacing: 0) {
            // Custom navigation bar
            navigationBar
            
            // Pinned home game (if any)
            pinnedGameView
            
            // MAIN SCROLLABLE CONTENT AREA
            ScrollViewReader { scrollView in
                ScrollView {
                    messageListContent
                }
                .onChange(of: groupService.groupMessages.count) { _ in
                    // Only scroll to bottom if not loading more messages (to avoid disrupting pagination)
                    if !isLoadingMoreMessages {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            scrollToBottom(in: scrollView)
                        }
                    }
                }
                .onChange(of: scrollToBottom) { newValue in
                    if newValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            scrollToBottom(in: scrollView)
                        }
                    }
                }
                .onChange(of: isKeyboardVisible) { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom(in: scrollView)
                    }
                }
                .onAppear {
                    // Scroll to bottom when view appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        scrollToBottom(in: scrollView)
                    }
                }
                .onChange(of: viewState) { newState in
                    // Scroll to bottom when view becomes ready
                    if case .ready = newState {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            scrollToBottom(in: scrollView)
                        }
                    }
                }
            }
        }
        .onViewLifecycle(appeared: "Ready state")
    }
    
    // MARK: - Error State View
    private var errorStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.yellow)
            
            Text("Error Loading Chat")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            
            if case .error(let message) = viewState {
                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button("Try Again") {
                viewState = .loading
                loadMessages()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .padding(.top, 10)
            
            Button("Go Back") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top, 10)
            .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onViewLifecycle(appeared: "Error state")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                // Main content
                mainContentView
                
                // INPUT BAR - positioned absolutely at the bottom, will move with keyboard
                inputBar
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationBarHidden(true)
        .task {
            // View was created
            viewCreatedTime = Date()

            
            // Don't wait for onAppear - preload messages immediately when task starts
            await preloadMessages()
        }
        .onAppear {
            // Hide navigation bar appearance itself, not just visibility
            UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
            UINavigationBar.appearance().shadowImage = UIImage()
            UINavigationBar.appearance().isTranslucent = true
            UINavigationBar.appearance().backgroundColor = .clear
            
            tabBarVisibility.isVisible = false
            
            // Set up Combine subscription to groupService
            setupSubscription()
            setupKeyboardObservers()
        }
        .onDisappear {
            // Restore navigation bar appearance
            UINavigationBar.appearance().setBackgroundImage(nil, for: .default)
            UINavigationBar.appearance().shadowImage = nil
            
            tabBarVisibility.isVisible = true
            
            // Clean up subscriptions
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
            removeKeyboardObservers()
            
            // Clean up the message listener
            groupService.cleanupGroupListener()
        }
        // REMOVED: Hand picker sheet
        /*
        .sheet(isPresented: $showingHandPicker) {
            HandHistorySelectionView { handId in
                sendHandHistory(handId)
                showingHandPicker = false
            }
            .environmentObject(handStore)
            .environmentObject(postService)
            .environmentObject(userService)
        }
        */
        .sheet(isPresented: $showingHomeGameView) {
            HomeGameView(groupId: group.id, onGameCreated: { game in
                // Create and send home game message
                sendHomeGameMessage(game)
                showingHomeGameView = false
            })
            .environmentObject(userService)
        }
        .sheet(isPresented: $showingImagePicker) {
            PhotosPicker(selection: $imagePickerItem, matching: .images) {
                Text("Select Photo")
            }
            .onChange(of: imagePickerItem) { newItem in
                Task {
                    do {

                        
                        guard let newItem = newItem else {

                            return
                        }
                        
                        let data = try await newItem.loadTransferable(type: Data.self)
                        
                        guard let data = data else {

                            throw NSError(domain: "ImageLoading", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not load image data"])
                        }
                        
                        guard let image = UIImage(data: data) else {

                            throw NSError(domain: "ImageLoading", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create image from data"])
                        }
                        

                        
                        // Clean up the picker item to allow selecting the same image again
                        await MainActor.run {
                            imagePickerItem = nil
                            selectedImage = image
                            sendImage(image)
                            showingImagePicker = false
                        }
                    } catch {

                        await MainActor.run {
                            self.error = "Failed to load image: \(error.localizedDescription)"
                            self.showError = true
                            imagePickerItem = nil
                            showingImagePicker = false
                        }
                    }
                }
            }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Error"),
                message: Text(error ?? "An unknown error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
        .background(Color.black)
        // Present the group detail view
        .fullScreenCover(isPresented: $isShowingGroupDetail) {
            GroupDetailView(group: $group)
                .navigationBarHidden(true)
        }
        // Global full-screen image viewer
        .fullScreenCover(item: $viewerImageURL) { imageItem in
            FullScreenImageView(imageURL: imageItem.url, onDismiss: { viewerImageURL = nil })
        }
    }
    
    // Setup Combine subscription to observe messages
    private func setupSubscription() {
        // Setup publisher subscription for messages
        groupService.$groupMessages
            .receive(on: RunLoop.main)
            .sink { newMessages in
                print("📬 GroupChatView: Received \(newMessages.count) messages from service")
                
                let previousCount = lastLoadedCount
                
                // Update pagination state
                if isLoadingMoreMessages {
                    let loadedCount = newMessages.count - lastLoadedCount
                    hasMoreMessages = loadedCount >= 30
                    isLoadingMoreMessages = false
                    shouldAutoScroll = false // Don't scroll when loading more messages
                } else {
                    // Check if this is a new message (count increased by 1) vs initial load
                    if previousCount > 0 && newMessages.count == previousCount + 1 {
                        // This is likely a new message from the listener - don't auto scroll
                        shouldAutoScroll = false
                        print("📨 New message detected - not auto-scrolling")
                    } else if previousCount == 0 {
                        // Initial load - should scroll
                        shouldAutoScroll = true
                        print("📥 Initial load - will auto-scroll")
                    }
                }
                
                // Store count for next pagination check
                lastLoadedCount = newMessages.count
                
                // Only scroll if we should auto-scroll
                if shouldAutoScroll && !isLoadingMoreMessages {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom = true
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // Preload messages using Task for better async handling
    private func preloadMessages() async {
        isLoadingMessages = true
        
        // Reset pagination state for initial load
        await MainActor.run {
            hasMoreMessages = true
            lastLoadedCount = 0
        }
        
        do {
            // Load initial messages
            try await groupService.fetchGroupMessages(groupId: group.id, limit: 30, loadMore: false)
            
            // Update UI on main thread
            await MainActor.run {
                isLoadingMessages = false
                viewState = .ready
                
                // Check if we have more messages
                hasMoreMessages = groupService.groupMessages.count >= 30
                
                // Look for active home games to pin
                loadActiveHomeGame()
                
                // Ensure we scroll to bottom after initial load
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    scrollToBottom = true
                }
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.showError = true
                isLoadingMessages = false
                viewState = .error(error.localizedDescription)
            }
        }
    }
    
    // Load and pin the most recent active home game
    private func loadActiveHomeGame() {
        // First, find if there's a home game message
        isPinnedGameLoading = true
        
        Task {
            do {
                // Use HomeGameService to fetch active games for this group
                let activeGames = try await homeGameService.fetchActiveGamesForGroup(groupId: group.id)
                
                await MainActor.run {
                    // Find the most recent active game
                    if let mostRecentGame = activeGames.first {
                        // Pin the most recent active game
                        self.pinnedHomeGame = mostRecentGame
                    } else {
                        // No active games found
                        self.pinnedHomeGame = nil
                    }
                    
                    self.isPinnedGameLoading = false
                }
            } catch {

                
                await MainActor.run {
                    self.isPinnedGameLoading = false
                    self.pinnedHomeGame = nil
                }
            }
        }
        
        // Alternatively, we can search for home game messages in the existing messages
        // and fetch the game details from there if the HomeGameService approach doesn't work
        /*
        for message in groupService.groupMessages.sorted(by: { $0.timestamp > $1.timestamp }) {
            if message.messageType == .homeGame, let gameId = message.homeGameId {
                Task {
                    do {
                        if let game = try await homeGameService.fetchHomeGame(gameId: gameId) {
                            if game.status == .active {
                                await MainActor.run {
                                    self.pinnedHomeGame = game
                                    self.isPinnedGameLoading = false
                                }
                                return
                            }
                        }
                    } catch {

                    }
                }
                break // Only try the most recent home game message
            }
        }
        
        // If we get here and still loading, no active game was found
        if isPinnedGameLoading {
            DispatchQueue.main.async {
                self.isPinnedGameLoading = false
            }
        }
        */
    }
    
    private func loadMessages() {
        Task {
            await preloadMessages()
        }
    }
    
    private func loadMoreMessages() {
        guard hasMoreMessages, !isLoadingMoreMessages else { return }
        
        isLoadingMoreMessages = true
        
        Task {
            do {
                // Load older messages
                try await groupService.fetchGroupMessages(
                    groupId: group.id, 
                    limit: 30, 
                    loadMore: true
                )
            } catch {
                await MainActor.run {
                    self.error = "Failed to load more messages: \(error.localizedDescription)"
                    self.showError = true
                    isLoadingMoreMessages = false
                }
            }
        }
    }
    
    private func sendTextMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let trimmedText = messageText
        messageText = ""
        isSendingMessage = true
        
        Task {
            do {
                try await groupService.sendTextMessage(groupId: group.id, text: trimmedText)
                await MainActor.run {
                    isSendingMessage = false
                    // Always scroll to bottom when user sends a message
                    shouldAutoScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        scrollToBottom = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    isSendingMessage = false
                    // Restore the message if sending failed
                    messageText = trimmedText
                }
            }
        }
    }
    
    private func sendImage(_ image: UIImage) {
        isSendingImage = true

        
        Task {
            do {
                // Add a small delay to ensure UI updates
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                try await groupService.sendImageMessage(groupId: group.id, image: image)

                
                await MainActor.run {
                    isSendingImage = false
                    // Always scroll to bottom when user sends an image
                    shouldAutoScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        scrollToBottom = true
                    }
                }
            } catch {

                
                await MainActor.run {
                    self.error = "Failed to upload image: \(error.localizedDescription)"
                    self.showError = true
                    isSendingImage = false
                }
            }
        }
    }
    
    // REMOVED: Hand history sending functionality
    /*
    private func sendHandHistory(_ handId: String) {
        Task {
            do {
                try await groupService.sendHandMessage(groupId: group.id, handHistoryId: handId)
                await MainActor.run {
                    // Always scroll to bottom when user sends a hand
                    shouldAutoScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        scrollToBottom = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
    */
    
    private func sendHomeGameMessage(_ game: HomeGame) {
        Task {
            do {
                try await groupService.sendHomeGameMessage(groupId: group.id, homeGame: game)
                await MainActor.run {
                    // Always scroll to bottom when user sends a home game
                    shouldAutoScroll = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        scrollToBottom = true
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
    
    // Helper function to group messages by sender and time (1 minute window)
    private func groupMessages(_ messages: [GroupMessage]) -> [MessageGroup] {
        guard !messages.isEmpty else { return [] }
        
        var result: [MessageGroup] = []
        var currentGroup: MessageGroup?
        
        for message in messages {
            // Check if message should be added to current group
            if let current = currentGroup,
               current.senderId == message.senderId,
               message.timestamp.timeIntervalSince(current.lastTimestamp) <= 60 { // 60 seconds = 1 minute
                // Add to current group
                current.messages.append(message)
                current.lastTimestamp = message.timestamp
            } else {
                // Create a new group
                if let current = currentGroup {
                    result.append(current)
                }
                currentGroup = MessageGroup(
                    id: message.id,
                    senderId: message.senderId,
                    senderName: message.senderName,
                    senderAvatarURL: message.senderAvatarURL,
                    messages: [message],
                    firstTimestamp: message.timestamp,
                    lastTimestamp: message.timestamp
                )
            }
        }
        
        // Add the last group
        if let current = currentGroup {
            result.append(current)
        }
        
        return result
    }
    
    // Helper function to scroll to bottom
    private func scrollToBottom(in scrollView: ScrollViewProxy) {
        withAnimation {
            scrollView.scrollTo("bottomAnchor", anchor: .bottom)
            scrollToBottom = false
        }
    }
    
    // Setup keyboard observers to track keyboard height and visibility
    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
               let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
                
                // Store animation duration from the keyboard notification
                self.keyboardAnimationDuration = duration
                self.keyboardHeight = keyboardFrame.height
                self.isKeyboardVisible = true
                
                // Trigger scroll to bottom to avoid content being hidden
                self.scrollToBottom = true
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
                // Use the same animation duration as the keyboard
                self.keyboardAnimationDuration = duration
                self.keyboardHeight = 0
                self.isKeyboardVisible = false
            }
        }
    }
    
    // Remove keyboard observers
    private func removeKeyboardObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    // Helper function to calculate and update text input height
    private func updateTextInputHeight(for text: String) {
        // Create a temporary UILabel to measure text height
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 16)
        label.numberOfLines = 0
        label.text = text.isEmpty ? "A" : text // Use "A" as minimum height reference
        
        // Calculate width available for text (total width minus padding and send button space)
        let availableWidth = UIScreen.main.bounds.width - 32 - 24 - 32 - 32 // padding + plus button + send button + text padding
        let constraintSize = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        
        let textSize = label.sizeThatFits(constraintSize)
        let newHeight = max(minInputHeight, min(maxInputHeight, textSize.height + 24)) // Add padding for top/bottom
        
        withAnimation(.easeOut(duration: 0.2)) {
            textInputHeight = newHeight
        }
    }
}

// Message group for displaying multiple messages from the same sender
class MessageGroup: Identifiable {
    let id: String
    let senderId: String
    let senderName: String
    let senderAvatarURL: String?
    var messages: [GroupMessage]
    let firstTimestamp: Date
    var lastTimestamp: Date
    
    init(id: String, senderId: String, senderName: String, senderAvatarURL: String?, messages: [GroupMessage], firstTimestamp: Date, lastTimestamp: Date) {
        self.id = id
        self.senderId = senderId
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.messages = messages
        self.firstTimestamp = firstTimestamp
        self.lastTimestamp = lastTimestamp
    }
}

// View for a group of messages
struct MessageGroupView: View {
    let messageGroup: MessageGroup
    var onImageTapped: (String) -> Void
    
    // Check if the current user is the sender
    private var isCurrentUser: Bool {
        return messageGroup.senderId == Auth.auth().currentUser?.uid
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isCurrentUser {
                Spacer()
            } else {
                // Avatar - only shown once per group
                ZStack {
                    Circle()
                        .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                        .frame(width: 36, height: 36)
                    
                    if let avatarURL = messageGroup.senderAvatarURL, let url = URL(string: avatarURL) {
                        KFImage(url)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.gray)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            }
            
            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {
                // Individual messages in the group
                ForEach(Array(messageGroup.messages.enumerated()), id: \.element.id) { index, message in
                    SingleMessageView(
                        message: message, 
                        isCurrentUser: isCurrentUser, 
                        senderName: messageGroup.senderName,
                        showSenderName: !isCurrentUser && index == 0, // Only show sender name on first message in group
                        onImageTapped: onImageTapped
                    )
                }
            }
            
            if !isCurrentUser {
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }
}

// View for a single message within a group
struct SingleMessageView: View {
    let message: GroupMessage
    let isCurrentUser: Bool
    let senderName: String
    let showSenderName: Bool
    var onImageTapped: (String) -> Void
    
    // Environment objects
    @EnvironmentObject private var userService: UserService
    // REMOVED: @EnvironmentObject private var handStore: HandStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityManager
    
    // Format the timestamp
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - Body
    var body: some View {
        messageContent
    }
    
    // MARK: - Message Content
    @ViewBuilder
    private var messageContent: some View {
        switch message.messageType {
        case .text:
            if let text = message.text {
                HStack {
                    if isCurrentUser {
                        Spacer(minLength: 50) // Leave space on the left for current user
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        // Sender name (only if not current user and should show)
                        if showSenderName {
                            Text(senderName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.leading, 2)
                        }
                        
                        HStack(alignment: .bottom, spacing: 6) {
                            Text(text)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            // Timestamp at bottom right
                            Text(formattedTime(message.timestamp))
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isCurrentUser ?
                                      Color(UIColor(red: 100/255, green: 150/255, blue: 255/255, alpha: 0.9)) :
                                      Color(UIColor(red: 40/255, green: 70/255, blue: 120/255, alpha: 0.9)))
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        )
                    }
                    
                    if !isCurrentUser {
                        Spacer(minLength: 50) // Leave space on the right for other users
                    }
                }
            } else {
                EmptyView()
            }
                case .image:
            if let imageURL = message.imageURL, let url = URL(string: imageURL) {
                HStack {
                    if isCurrentUser {
                        Spacer(minLength: 40)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Sender name (only if not current user and should show)
                        if showSenderName {
                            Text(senderName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.leading, 2)
                        }
                        
                        ZStack(alignment: .bottomTrailing) {
                            // Image with proper sizing - no background
                            KFImage(url)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 220, maxHeight: 260)
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                                .onTapGesture {
                                    onImageTapped(imageURL)
                                }
                            
                            // Timestamp overlay
                            Text(formattedTime(message.timestamp))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.7))
                                )
                                .padding(.trailing, 8)
                                .padding(.bottom, 8)
                        }
                    }
                    
                    if !isCurrentUser {
                        Spacer(minLength: 40)
                    }
                }
            } else {
                EmptyView()
            }
        
        case .hand:
            // REMOVED: Hand message functionality for launch
            EmptyView()
            
        case .homeGame:
            if let gameId = message.homeGameId {
                HStack {
                    if isCurrentUser {
                        Spacer(minLength: 40)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        // Sender name (only if not current user and should show)
                        if showSenderName {
                            Text(senderName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                                .padding(.leading, 2)
                        }
                        
                        VStack(spacing: 6) {
                            HomeGamePreview(gameId: gameId,
                                            ownerId: message.senderId,
                                            groupId: message.groupId)
                                .environmentObject(userService)
                                .environmentObject(sessionStore)
                                .environmentObject(postService)
                                .environmentObject(tabBarVisibility)
                            
                            HStack {
                                Spacer()
                                Text(formattedTime(message.timestamp))
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    if !isCurrentUser {
                        Spacer(minLength: 40)
                    }
                }
            } else {
                EmptyView()
            }
        }
    }
}

// REMOVED: Hand message view functionality - all hand-related code has been commented out for launch

