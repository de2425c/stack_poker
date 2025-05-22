import SwiftUI
import FirebaseFirestore
import PhotosUI
import UIKit

/// A versatile post editor view that can be used for both regular posts and hand posts.
/// This component is shared between the FeedView (for creating text/image posts) and
/// HandReplayView (for sharing poker hands).
struct PostEditorView: View {
    // Environment objects and state
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    @EnvironmentObject var handStore: HandStore
    @EnvironmentObject var sessionStore: SessionStore

    // Required properties
    let userId: String

    // Optional properties passed initially
    var initialText: String
    // Use @State for the hand so it can be modified by hand selection
    @State private var hand: ParsedHandHistory?
    var sessionId: String?
    var isSessionPost: Bool
    var isNote: Bool  // New property to identify note posts
    var showFullSessionCard: Bool // New property to control session card display
    var sessionGameName: String // Direct game name for badge
    var sessionStakes: String // Direct stakes for badge

    // View state
    @State private var postText = ""
    @State private var isLoading = false
    @State private var selectedImages: [UIImage] = []
    @State private var imageSelection: [PhotosPickerItem] = []
    @State private var showingHandSelection = false
    @State private var location: String = ""
    @FocusState private var isTextEditorFocused: Bool

    // State for selected completed session
    @State private var selectedCompletedSession: Session? = nil
    @State private var showingSessionSelection = false
    @State private var completedSessionTitle: String = ""

    // Initializer to set up the initial hand state
    init(userId: String,
         initialText: String = "",
         initialHand: ParsedHandHistory? = nil, // Renamed for clarity in init
         sessionId: String? = nil,
         isSessionPost: Bool = false,
         isNote: Bool = false,
         showFullSessionCard: Bool = false,
         sessionGameName: String = "",
         sessionStakes: String = "") {
        self.userId = userId
        self.initialText = initialText
        _hand = State(initialValue: initialHand) // Initialize @State hand
        self.sessionId = sessionId
        self.isSessionPost = isSessionPost
        self.isNote = isNote
        self.showFullSessionCard = showFullSessionCard
        self.sessionGameName = sessionGameName
        self.sessionStakes = sessionStakes
    }

    // Determines if this is a hand post
    private var isHandPost: Bool {
        hand != nil
    }

    // Create a SessionCard component to display full session details
    private struct SessionCard: View {
        let text: String

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Parse the session text
                if let parsed = parseSessionText(from: text) {
                    // Session header
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))

                        Text("Live Session")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()
                    }

                    // Divider
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 1)

                    // Game and stakes
                    Text(parsed.gameName + " (\(parsed.stakes))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)

                    // Stack and profit
                    HStack {
                        Text("Stack: $\(parsed.stack)")
                            .font(.system(size: 15))
                            .foregroundColor(.white.opacity(0.9))

                        Spacer()

                        Text(parsed.profit)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(parsed.profit.contains("+") ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red)
                    }

                    // Session duration
                    Text("Duration: \(parsed.time)")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 28/255, green: 30/255, blue: 34/255))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 1)
            )
        }

        // Helper method to parse session text
        private func parseSessionText(from text: String) -> (gameName: String, stakes: String, stack: String, profit: String, time: String)? {
            let lines = text.components(separatedBy: "\n")
            guard lines.count >= 3 else { return nil }

            var gameName = "Cash Game"
            var stakes = "$1/$2"
            var stack = "0"
            var profit = "+$0"
            var time = "0h 0m"

            for line in lines {
                if line.hasPrefix("Session at ") {
                    // Parse "Session at Wynn ($2/$5/$10)"
                    if let range = line.range(of: "Session at "),
                       let stakeRange = line.range(of: "(", range: range.upperBound..<line.endIndex),
                       let endStakeRange = line.range(of: ")", range: stakeRange.upperBound..<line.endIndex) {

                        let gameNameRange = range.upperBound..<stakeRange.lowerBound
                        let stakesRange = stakeRange.upperBound..<endStakeRange.lowerBound

                        gameName = String(line[gameNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        stakes = String(line[stakesRange])
                    }
                } else if line.hasPrefix("Stack: $") {
                    // Parse "Stack: $1200 (+$200)"
                    let components = line.components(separatedBy: " ")
                    if components.count >= 2 {
                        stack = components[1].replacingOccurrences(of: "$", with: "")

                        if components.count >= 3 {
                            profit = components[2].replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
                        }
                    }
                } else if line.hasPrefix("Time: ") {
                    // Parse "Time: 2h 30m"
                    time = line.replacingOccurrences(of: "Time: ", with: "")
                }
            }

            return (gameName, stakes, stack, profit, time)
        }
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    // Background
                    AppBackgroundView().ignoresSafeArea()

                    VStack(spacing: 0) {
                        // Header with user profile
                        profileHeaderView
                            .padding(.top, 20) // Reduced top padding to move UI upward

                        // Session display section
                        sessionDisplayView

                        // Note view (only for note posts)
                        if isNote {
                            SharedNoteView(note: initialText)
                                .padding(.horizontal)
                        }

                        // Hand Summary (only for hand posts)
                        if isHandPost, let handData = hand {
                            HandSummaryView(hand: handData)
                                .padding(.horizontal)
                            locationTextField
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                        }

                        // Completed Session Display
                        if let completedSession = selectedCompletedSession {
                            VStack(alignment: .leading, spacing: 10) {
                                // Session Title TextField - Strava Style
                                TextField("Session Title", text: $completedSessionTitle)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.bottom, 2)

                                // Caption TextEditor - Directly below title
                                TextEditor(text: $postText) // Using postText for caption here
                                    .foregroundColor(postText == "Describe your session..." ? .gray.opacity(0.6) : .white) // Placeholder color
                                    .font(.system(size: 16))
                                    .frame(height: 80) // Fixed height for caption editor
                                    .scrollContentBackground(.hidden)
                                    .background(Color.black.opacity(0.1))
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        if postText == "Describe your session..." {
                                            postText = "" // Clear placeholder on tap
                                        }
                                    }
                                    .onAppear {
                                        if postText.isEmpty { // Set placeholder if empty
                                            postText = "Describe your session..."
                                        }
                                    }
                                    .padding(.bottom, 12)
                                
                                // Session Stats - Strava-like prominent display
                                // Arrange in HStacks for a row-based metric display
                                VStack(alignment: .leading, spacing: 16) { // Overall container for stats
                                    HStack(spacing: 16) {
                                        SessionStatMetricView(label: "Game", value: "\(completedSession.gameName) @ \(completedSession.stakes)", isWide: true)
                                    }
                                    HStack(spacing: 16) {
                                        SessionStatMetricView(label: "Duration", value: String(format: "%.1f hr", completedSession.hoursPlayed))
                                        SessionStatMetricView(label: "Buy-in", value: String(format: "$%.0f", completedSession.buyIn))
                                    }
                                    HStack(spacing: 16) {
                                        SessionStatMetricView(label: "Cashout", value: String(format: "$%.0f", completedSession.cashout))
                                        SessionStatMetricView(label: "Profit", value: String(format: "$%.2f", completedSession.profit), 
                                                            valueColor: completedSession.profit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                                    }
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 15)
                        } else {
                            // Text Editor for regular posts / notes / hands (not a completed session share)
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $postText)
                                    .focused($isTextEditorFocused)
                                    .foregroundColor(.white)
                                    .font(.system(size: 16))
                                    .scrollContentBackground(.hidden)
                                    .padding()
                                    .background(Color.clear)
                                    .frame(minHeight: 100, idealHeight: 200 ,maxHeight: .infinity)

                                if postText.isEmpty && !isTextEditorFocused {
                                    Text(placeholderText) // Original placeholder logic
                                        .foregroundColor(Color.gray)
                                        .font(.system(size: 16))
                                        .padding(.horizontal, 20)
                                        .padding(.top, 24)
                                }
                            }
                        }

                        // Spacer() // Pushes buttons to the bottom - this might need to be conditional or removed if stats are large
                        Spacer(minLength: selectedCompletedSession != nil ? 20 : 0) // Add more space if session details are shown

                        // Image picker and preview (only for regular posts)
                        if !isHandPost && !isNote {
                            actionButtonsView
                        }
                    }
                    .padding(.bottom, 100) // Reduced bottom padding to lift action buttons
                }
            }
            .ignoresSafeArea(.keyboard) // Prevent keyboard from pushing content up
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: isHandPost ? shareHand : createPost) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isHandPost ? "Share" : "Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isPostDisabled)
                    .foregroundColor(isPostDisabled ? .gray : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
            }
            .onChange(of: imageSelection) { newValue in
                Task {
                    selectedImages.removeAll()
                    for item in newValue {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            selectedImages.append(image)
                        }
                    }
                }
            }
            // Close keyboard when Return key is pressed (TextEditor inserts "\n")
            .onChange(of: postText) { newValue in
                if newValue.last == "\n" {
                    // Remove the newline and dismiss keyboard
                    postText.removeLast()
                    isTextEditorFocused = false
                }
            }
            .onAppear {
                if !initialText.isEmpty {
                    if !isNote && !showFullSessionCard {
                        postText = initialText
                    }
                }
                isTextEditorFocused = true
                if userService.currentUserProfile == nil {
                    Task {
                        try? await userService.fetchUserProfile()
                    }
                }
            }
        }
        .sheet(isPresented: $showingHandSelection) {
            HandHistorySelectionView(onHandSelected: { handId in
                Task {
                    if let fetchedSavedHand = await handStore.fetchHandById(handId) {
                        self.hand = fetchedSavedHand.hand // Assign directly to @State var hand
                    }
                }
            })
            .environmentObject(HandStore(userId: userId))
        }
        .sheet(isPresented: $showingSessionSelection) {
            SessionSelectionView(onSessionSelected: { session in
                self.selectedCompletedSession = session
                // Optionally pre-fill postText or handle session details here
            })
            .environmentObject(sessionStore) // Pass the sessionStore
        }
    }

    // Computed properties for UI customization
    private var navigationTitle: String {
        if isSessionPost {
            return "Share Session Update"
        } else if isHandPost {
            return "Share Hand"
        } else if isNote {
            return "Share Note"
        } else {
            return "Create Post"
        }
    }

    // Add computed property for button disabled state
    private var isPostDisabled: Bool {
        if selectedCompletedSession != nil {
            // For completed session posts, only title is required.
            return completedSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || userService.currentUserProfile == nil
        }
        // Original logic for other post types
        let isEmpty = postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let allowEmptyPost = isNote || showFullSessionCard
        return (isEmpty && !allowEmptyPost) || isLoading || userService.currentUserProfile == nil
    }

    private var placeholderText: String {
        if selectedCompletedSession != nil {
            return "Describe your session..." // This won't be used by TextEditor directly if we handle placeholder manually
        } else if isSessionPost {
            return "Share your session update..."
        } else if isHandPost {
            return "Add a comment about your hand..."
        } else if isNote {
            return "Add a comment about your note..."
        } else {
            return "What's on your mind?"
        }
    }

    // Helper to find and extract session details from text
    private func extractSessionDetails() -> String {
        // Check if there are session details in the initialText
        if initialText.contains("Session at ") {
            // Extract the session details section
            let lines = initialText.components(separatedBy: "\n")
            var sessionLines: [String] = []
            var foundSessionLine = false

            for line in lines {
                if line.hasPrefix("Session at ") {
                    foundSessionLine = true
                }

                if foundSessionLine && (line.hasPrefix("Session at ") || line.hasPrefix("Stack:") || line.hasPrefix("Time:")) {
                    sessionLines.append(line)
                }
            }

            if !sessionLines.isEmpty {
                return sessionLines.joined(separator: "\n")
            }
        }

        // If specific session details aren't found, but we have a session ID,
        // create some default session info using the parsed session info
        if let (gameName, stakes) = parseSessionInfo(), sessionId != nil {
            // Build simplified session details
            return """
            Session at \(gameName) (\(stakes))
            Stack: $0 (+$0)
            Time: 0h 0m
            """
        }

        // Fallback to the initialText if no session details found
        return initialText
    }

    // First, add new function to parse session info from the session details
    private func parseSessionInfo() -> (gameName: String, stakes: String)? {
        guard let sessionId = sessionId,
              isSessionPost else {
            return nil
        }

        // Try to extract from initialText first
        if initialText.contains("Session at ") {
            if let range = initialText.range(of: "Session at "),
               let stakeRange = initialText.range(of: "(", range: range.upperBound..<initialText.endIndex),
               let endStakeRange = initialText.range(of: ")", range: stakeRange.upperBound..<initialText.endIndex) {

                let gameNameRange = range.upperBound..<stakeRange.lowerBound
                let stakesRange = stakeRange.upperBound..<endStakeRange.lowerBound

                let gameName = String(initialText[gameNameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let stakes = String(initialText[stakesRange])

                return (gameName, stakes)
            }
        }

        return nil
    }

    // Update the post creation logic to work with different content types
    private func createPost() {
        // For completed session, ensure title is present
        if selectedCompletedSession != nil && completedSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("Error: Session title is required when sharing a completed session.")
            // Optionally show an alert to the user
            return
        }
        
        guard (postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (isNote || showFullSessionCard || selectedCompletedSession != nil)) || !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let username = userService.currentUserProfile?.username else { return }

        let displayName = userService.currentUserProfile?.displayName
        let profileImage = userService.currentUserProfile?.avatarURL

        // Handle different content types:
        var content: String

        // Prepend completed session details if selected
        if let session = selectedCompletedSession {
            // Ensure title is not empty, provide a default if necessary or handle error
            let titleToUse = completedSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Session Report" : completedSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            
            let sessionDetails = "COMPLETED_SESSION_INFO: Title: \(titleToUse), Game: \(session.gameName), Stakes: \(session.stakes), Duration: \(String(format: "%.1f", session.hoursPlayed))hrs, Buy-in: $\(Int(session.buyIn)), Cashout: $\(Int(session.cashout)), Profit: $\(String(format: "%.2f", session.profit))\n"
            content = sessionDetails + postText // postText is now the caption
        } else {
            // This is the original logic for non-completed-session posts
            // Make sure session info is included at the start of the content for notes and hands
            if isSessionPost && !sessionGameName.isEmpty && !sessionStakes.isEmpty && (isNote || isHandPost) {
                // Add session info in a format that can be parsed in the feed
                let sessionInfo = "SESSION_INFO:\(sessionGameName):\(sessionStakes)\n"

                // For note posts with no additional comment
                if isNote && postText.isEmpty {
                    content = sessionInfo + "Note: " + initialText
                }
                // For note posts with a comment
                else if isNote && !postText.isEmpty {
                    content = sessionInfo + postText + "\n\nNote: " + initialText
                }
                // For hand posts
                else if isHandPost {
                    content = sessionInfo + postText
                }
                // Default case - should not happen for notes/hands
                else {
                    content = initialText
                }
            }
            // For chip updates (showing full session card) or non-session posts
            else {
                if isNote && postText.isEmpty {
                    content = initialText
                } else if isNote && !postText.isEmpty {
                    content = postText + "\n\nNote: " + initialText
                } else if showFullSessionCard && postText.isEmpty {
                    content = initialText
                } else if showFullSessionCard && !postText.isEmpty {
                    content = initialText + "\n\n" + postText
                } else {
                    content = postText
                }
            }
        }

        isLoading = true

        Task {
            do {
                try await postService.createPost(
                    content: content,
                    userId: userId,
                    username: username,
                    displayName: displayName,
                    profileImage: profileImage,
                    images: selectedImages.isEmpty ? nil : selectedImages,
                    sessionId: sessionId
                )
                try await postService.fetchPosts()
                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } catch {
                print("Error creating post: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }

    // Share a hand post
    private func shareHand() {
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let hand = hand,
              let username = userService.currentUserProfile?.username else { return }

        let profileImage = userService.currentUserProfile?.avatarURL
        let displayName = userService.currentUserProfile?.displayName

        // Add session info for hands if available
        var handPostContent = postText
        if isSessionPost && !sessionGameName.isEmpty && !sessionStakes.isEmpty {
            // Add session info in a format that can be parsed in the feed
            let sessionInfo = "SESSION_INFO:\(sessionGameName):\(sessionStakes)\n"
            handPostContent = sessionInfo + postText
        }

        isLoading = true

        Task {
            do {
                try await postService.createHandPost(
                    content: handPostContent,
                    userId: userId,
                    username: username,
                    displayName: displayName,
                    profileImage: profileImage,
                    hand: hand,
                    sessionId: sessionId,
                    location: location
                )
                try await postService.fetchPosts()
                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } catch {
                print("Error sharing hand: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }

    // MARK: - View Builders

    @ViewBuilder
    private var profileHeaderView: some View {
        HStack(spacing: 12) {
            profileImageView

            VStack(alignment: .leading, spacing: 4) {
                profileNameView
                profileSubtitleView
            }

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var profileImageView: some View {
        if let profileImage = userService.currentUserProfile?.avatarURL {
            AsyncImage(url: URL(string: profileImage)) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                defaultProfileCircle
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            defaultProfileCircle
        }
    }

    @ViewBuilder
    private var defaultProfileCircle: some View {
        Circle()
            .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.gray)
            )
    }

    @ViewBuilder
    private var profileNameView: some View {
        if let displayName = userService.currentUserProfile?.displayName,
           !displayName.isEmpty {
            Text(displayName)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        } else if let username = userService.currentUserProfile?.username {
            Text(username)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var profileSubtitleView: some View {
        if isSessionPost {
            Text("Session Post")
                .font(.system(size: 14))
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
        } else {
            Text(isHandPost ? "Share your hand" : (isNote ? "Share your note" : "Create a post"))
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private var sessionDisplayView: some View {
        if isSessionPost && sessionId != nil {
            if showFullSessionCard {
                // For chip updates: full session card
                SessionCard(text: extractSessionDetails())
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            } else {
                sessionBadgeView
            }
        }
    }

    @ViewBuilder
    private var sessionBadgeView: some View {
        if !sessionGameName.isEmpty && !sessionStakes.isEmpty {
            SessionBadgeView(gameName: sessionGameName, stakes: sessionStakes)
                .padding(.horizontal)
                .padding(.bottom, 8)
        } else if let sessionInfo = parseSessionInfo() {
            SessionBadgeView(gameName: sessionInfo.gameName, stakes: sessionInfo.stakes)
                .padding(.horizontal)
                .padding(.bottom, 8)
        } else {
            genericSessionBadge
        }
    }

    @ViewBuilder
    private var genericSessionBadge: some View {
        HStack {
            Image(systemName: "gamecontroller.fill")
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8)))

            Text("Live Poker Session")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.8)))

            Spacer()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var textEditorView: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $postText)
                .focused($isTextEditorFocused)
                .foregroundColor(.white)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding()
                .background(Color.clear)
                .frame(minHeight: 100, idealHeight: 200 ,maxHeight: .infinity)

            if postText.isEmpty && !isTextEditorFocused {
                Text(placeholderText)
                    .foregroundColor(Color.gray)
                    .font(.system(size: 16))
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
            }
        }
    }

    @ViewBuilder
    private var actionButtonsView: some View {
        VStack(spacing: 8) {
            // Action buttons in a scrollable view to prevent overflow
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) { 
                    photoPickerButton
                    handPickerButton
                    sessionPickerButton 
                }
                .padding(.horizontal, 16) 
            }
            .frame(height: 100) // Adjusted ScrollView height for smaller buttons

            // Selected images preview
            if !selectedImages.isEmpty {
                selectedImagesPreview
            }
        }
        .padding(.vertical, 4)
        .padding(.bottom, 0) // Reduced bottom padding to lift buttons higher
    }

    @ViewBuilder
    private var photoPickerButton: some View {
        PhotosPicker(selection: $imageSelection, maxSelectionCount: 4, matching: .images) {
            VStack(spacing: 6) { 
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 22)) 
                Text("Add Photo")
                    .font(.system(size: 12, weight: .medium)) 
            }
            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            .frame(width: 80, height: 80) 
            .background(
                RoundedRectangle(cornerRadius: 10) 
                    .fill(Color.white.opacity(0.1))
            )
        }
    }

    @ViewBuilder
    private var selectedImagesPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<selectedImages.count, id: \.self) { index in
                    imagePreviewItem(at: index)
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func imagePreviewItem(at index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: selectedImages[index])
                .resizable()
                .scaledToFill()
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: {
                selectedImages.remove(at: index)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
                    .background(
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 20, height: 20)
                    )
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private var handPickerButton: some View {
        Button(action: {
            showingHandSelection = true
        }) {
            VStack(spacing: 6) { 
                Image(systemName: "suit.spade.fill") 
                    .font(.system(size: 22)) 
                Text("Add Hand")
                    .font(.system(size: 12, weight: .medium)) 
            }
            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            .frame(width: 80, height: 80) 
            .background(
                RoundedRectangle(cornerRadius: 10) 
                    .fill(Color.white.opacity(0.1))
            )
        }
    }

    @ViewBuilder
    private var sessionPickerButton: some View {
        Button(action: {
            // Placeholder: Action for showing session selection
            // print("Add Session button tapped")
            // TODO: Implement showing session selection view
            self.showingSessionSelection = true 
        }) {
            VStack(spacing: 6) { 
                Image(systemName: "list.bullet.clipboard.fill") 
                    .font(.system(size: 22)) 
                Text("Add Session")
                    .font(.system(size: 12, weight: .medium)) 
            }
            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            .frame(width: 80, height: 80) 
            .background(
                RoundedRectangle(cornerRadius: 10) 
                    .fill(Color.white.opacity(0.1))
            )
        }
    }

    @ViewBuilder
    private var locationTextField: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            TextField("Location (e.g., Bellagio)", text: $location)
                .foregroundColor(.white)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 1.0)))
        )
        .padding(.top, 4) 
    }
}

// Define SessionStatMetricView helper view here
private struct SessionStatMetricView: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    var isWide: Bool = false // For stats like Game Name that might need more width

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .bold)) // Prominent value
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 12, weight: .medium)) // Smaller label
                .foregroundColor(.gray)
        }
        .frame(maxWidth: isWide ? .infinity : nil, alignment: isWide ? .leading : .center)
    }
}