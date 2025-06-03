import SwiftUI
import FirebaseAuth
import PhotosUI
import Combine
import Foundation
import FirebaseStorage
import FirebaseFirestore
import Kingfisher

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
    private let groupService = GroupService()
    private let homeGameService = HomeGameService()
    @EnvironmentObject private var handStore: HandStore
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityManager
    
    // State for messages that we manually update from the subscription
    @State private var messages: [GroupMessage] = []
    @State private var messageText = ""
    @State private var showingImagePicker = false
    @State private var showingHandPicker = false
    @State private var showingHomeGameView = false
    @State private var selectedImage: UIImage?
    @State private var imagePickerItem: PhotosPickerItem?
    @State private var isLoadingMessages = false
    @State private var isSendingMessage = false
    @State private var isSendingImage = false
    @State private var error: String?
    @State private var showError = false
    @State private var viewState: ViewState = .loading
    
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
    
    let group: UserGroup
    
    // Add pinnedHomeGame state
    @State private var pinnedHomeGame: HomeGame?
    @State private var isPinnedGameLoading = false
    
    // Enhanced keyboard tracking properties
    @State private var keyboardHeight: CGFloat = 0
    @State private var isKeyboardVisible = false
    @State private var keyboardAnimationDuration: Double = 0.25
    
    // Enum to track view state
    enum ViewState {
        case loading
        case ready
        case error(String)
    }
    
    @State private var isShowingGroupDetail = false
    
    // Global image viewer state for full-screen images
    @State private var viewerImageURL: String? = nil
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                // Main content
                ZStack {
                    // Content based on view state
                    switch viewState {
                    case .loading:
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
                        
                    case .ready:
                        VStack(spacing: 0) {
                            // Custom navigation bar
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
                            // Header now sits flush at top
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            
                            // Pinned home game (if any)
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
                            
                            // MAIN SCROLLABLE CONTENT AREA
                            ScrollViewReader { scrollView in
                                ScrollView {
                                    VStack(spacing: 0) {
                                        // Removed unnecessary top spacer so messages start right under the header
                                        Spacer().frame(height: 0)
                                        
                                        if isLoadingMessages && messages.isEmpty {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                .scaleEffect(1.5)
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .padding(.vertical, 100)
                                        } else if messages.isEmpty {
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
                                            let groupedMessages = groupMessages(messages)
                                            
                                            // Message groups with proper spacing
                                            LazyVStack(spacing: 8) {
                                                ForEach(groupedMessages, id: \.id) { messageGroup in
                                                    MessageGroupView(messageGroup: messageGroup, onImageTapped: { url in
                                                        viewerImageURL = url
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
                                .onChange(of: messages.count) { _ in
                                    scrollToBottom(in: scrollView)
                                }
                                .onChange(of: scrollToBottom) { newValue in
                                    if newValue {
                                        scrollToBottom(in: scrollView)
                                    }
                                }
                                .onChange(of: isKeyboardVisible) { _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        scrollToBottom(in: scrollView)
                                    }
                                }
                                .onAppear {
                                    scrollToBottom(in: scrollView)
                                }
                            }
                        }
                        .onViewLifecycle(appeared: "Ready state")
                        
                    case .error(let message):
                        VStack(spacing: 20) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.yellow)
                            
                            Text("Error Loading Chat")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(message)
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                            
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
                }
                
                // INPUT BAR - positioned absolutely at the bottom, will move with keyboard
                VStack(spacing: 0) {
                    Divider().background(Color.gray.opacity(0.3))
                    
                    HStack(spacing: 12) {
                        // + Button with menu
                        Menu {
                            Button(action: {
                                imagePickerItem = nil
                                showingImagePicker = true
                            }) {
                                Label("Photo", systemImage: "photo")
                            }
                            
                            Button(action: {
                                showingHandPicker = true
                            }) {
                                Label("Hands", systemImage: "doc.text")
                            }
                            
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
                        
                        // Text input field
                        ZStack(alignment: .trailing) {
                            TextField("Message", text: $messageText)
                                .focused($isTextFieldFocused)
                                .padding(12)
                                .background(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                                .cornerRadius(20)
                                .foregroundColor(.white)
                                .submitLabel(.send)
                                .onSubmit {
                                    if !messageText.isEmpty {
                                        sendTextMessage()
                                    }
                                }
                            
                            // Send button
                            if !messageText.isEmpty {
                                Button(action: sendTextMessage) {
                                    Image(systemName: isSendingMessage ? "circle" : "arrow.up.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                        .padding(.trailing, 8)
                                        .overlay(
                                            Group {
                                                if isSendingMessage {
                                                    ProgressView()
                                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                                                        .padding(.trailing, 8)
                                                }
                                            }
                                        )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(UIColor(red: 25/255, green: 25/255, blue: 30/255, alpha: 0.95)))
                // Move up with keyboard using proper animation with extra 5pt padding
                .offset(y: -keyboardHeight - (isKeyboardVisible ? 5 : 0))
                .animation(.easeOut(duration: keyboardAnimationDuration), value: keyboardHeight)
                // Fixed: Remove bottom padding to make input bar flush with bottom of screen
                .padding(.bottom, 0)
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
        }
        .sheet(isPresented: $showingHandPicker) {
            HandHistorySelectionView { handId in
                sendHandHistory(handId)
                showingHandPicker = false
            }
            .environmentObject(handStore)
            .environmentObject(postService)
            .environmentObject(userService)
        }
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
            GroupDetailView(group: group)
                .navigationBarHidden(true)
        }
        // Remove sheet-specific presentation settings
        .onPreferenceChange(ViewRenderTimeKey.self) { _ in
            // Debug - capture render end time
            renderEndTime = Date()

        }
        .preference(key: ViewRenderTimeKey.self, value: Date())
        // Global full-screen image viewer
        .fullScreenCover(item: $viewerImageURL) { url in
            FullScreenImageView(imageURL: url, onDismiss: { viewerImageURL = nil })
        }
    }
    
    // Setup Combine subscription to observe messages
    private func setupSubscription() {

        
        // Setup publisher subscription for messages
        groupService.$groupMessages
            .receive(on: RunLoop.main)
            .sink { newMessages in

                messages = newMessages
            }
            .store(in: &cancellables)
    }
    
    // Preload messages using Task for better async handling
    private func preloadMessages() async {
        let startTime = Date()

        isLoadingMessages = true
        
        do {
            // Use Task.sleep to simulate a delay, remove in production
            // try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            // Use new thread with high priority for fetching
            try await Task.detached(priority: .userInitiated) {
                let fetchStart = Date()
                
                // Start loading immediately
                try await groupService.fetchGroupMessages(groupId: group.id)
                
                let fetchEnd = Date()
            }.value
            
            let endTime = Date()
            
            // Update UI on main thread
            await MainActor.run {
                let uiStart = Date()
                
                isLoadingMessages = false
                viewState = .ready
                
                // Look for active home games to pin
                loadActiveHomeGame()
                
                let uiEnd = Date()
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
        for message in messages.sorted(by: { $0.timestamp > $1.timestamp }) {
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
    
    private func sendHandHistory(_ handId: String) {
        Task {
            do {
                try await groupService.sendHandMessage(groupId: group.id, handHistoryId: handId)
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }
    
    private func sendHomeGameMessage(_ game: HomeGame) {
        Task {
            do {
                try await groupService.sendHomeGameMessage(groupId: group.id, homeGame: game)
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
    
    // Format the timestamp
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
                // Sender name - only shown once per group for non-current user
                if !isCurrentUser {
                    Text(messageGroup.senderName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.bottom, 2)
                }
                
                // Individual messages in the group
                VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 3) {
                    ForEach(messageGroup.messages, id: \.id) { message in
                        SingleMessageView(message: message, isCurrentUser: isCurrentUser, onImageTapped: onImageTapped)
                    }
                }
                
                // Last message timestamp
                Text(formattedTime(messageGroup.lastTimestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.top, 2)
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
    var onImageTapped: (String) -> Void
    
    // Environment objects
    @EnvironmentObject private var userService: UserService
    @EnvironmentObject private var handStore: HandStore
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var tabBarVisibility: TabBarVisibilityManager
    
    // No local state for full-screen viewer; handled by parent.
    
    // MARK: - Body
    var body: some View {
        ZStack {
            messageContent
        }
    }
    
    // MARK: - Message Content
    @ViewBuilder
    private var messageContent: some View {
        switch message.messageType {
        case .text:
            if let text = message.text {
                Text(text)
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(isCurrentUser ?
                                  Color(UIColor(red: 30/255, green: 100/255, blue: 50/255, alpha: 1.0)) :
                                  Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                            .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                    )
            } else {
                EmptyView()
            }
        case .image:
            if let imageURL = message.imageURL, let url = URL(string: imageURL) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 200, maxHeight: 150)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onImageTapped(imageURL)
                    }
            } else {
                EmptyView()
            }
        case .hand:
            if let handId = message.handHistoryId {
                HandMessageView(handId: handId, ownerUserId: message.handOwnerUserId ?? message.senderId)
                    .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
            } else {
                EmptyView()
            }
        case .homeGame:
            if let gameId = message.homeGameId {
                HomeGamePreview(gameId: gameId,
                                ownerId: message.senderId,
                                groupId: message.groupId)
                    .environmentObject(userService)
                    .environmentObject(handStore)
                    .environmentObject(sessionStore)
                    .environmentObject(postService)
                    .environmentObject(tabBarVisibility)
            } else {
                EmptyView()
            }
        }
    }
}

// Replacement for ChatHandPreview using HandDisplayCardView
struct HandMessageView: View {
    let handId: String
    let ownerUserId: String
    
    @State private var isLoading = true
    @State private var showingDetail = false
    @State private var savedHand: SavedHand?
    @State private var loadError: String?
    @State private var showError = false
    
    @EnvironmentObject private var handStore: HandStore
    @EnvironmentObject private var postService: PostService
    @EnvironmentObject private var userService: UserService
    
    private var userId: String {
        Auth.auth().currentUser?.uid ?? ""
    }
    
    var body: some View {
        Button(action: {
            if savedHand != nil {
                showingDetail = true
            } else if loadError != nil {
                showError = true
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                } else if let hand = savedHand {
                    // Use HandDisplayCardView for displaying the hand
                    HandDisplayCardView(
                        hand: hand.hand, 
                        onReplayTap: { showingDetail = true },
                        location: nil,
                        createdAt: hand.timestamp,
                        showReplayInFeed: false
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 0.8)))
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
                } else {
                    Text(loadError ?? "Hand not found")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 0.5)))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            if let hand = savedHand {
                HandReplayView(hand: hand.hand, userId: userId)
                    .environmentObject(postService)
                    .environmentObject(userService)
            }
        }
        .alert(isPresented: $showError) {
            Alert(
                title: Text("Hand Not Available"),
                message: Text(loadError ?? "The hand history could not be loaded."),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            fetchHand()
        }
    }
    
    private func fetchHand() {
        isLoading = true
        loadError = nil
        
        // Try to get the hand from the user's own collection first
        if let hand = handStore.savedHands.first(where: { $0.id == handId }) {
            savedHand = hand
            isLoading = false
            return
        }
        
        // If not found, try to fetch it as a shared hand
        Task {
            do {
                if let shared = try await handStore.fetchSharedHand(handId: handId, ownerUserId: ownerUserId) {
                    await MainActor.run {
                        savedHand = shared
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        loadError = "This hand is no longer available."
                        isLoading = false
                    }
                }
            } catch {

                await MainActor.run {
                    loadError = "Failed to load hand: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

// Custom preference key to track view rendering time 
struct ViewRenderTimeKey: PreferenceKey {
    static var defaultValue: Date = Date()
    
    static func reduce(value: inout Date, nextValue: () -> Date) {
        value = nextValue()
    }
}

