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
    
    // Required properties
    let userId: String
    
    // Optional properties
    var initialText: String = ""
    var hand: ParsedHandHistory?
    var sessionId: String? = nil
    var isSessionPost: Bool = false
    var isNote: Bool = false  // New property to identify note posts
    var showFullSessionCard: Bool = false // New property to control session card display
    
    // View state
    @State private var postText = ""
    @State private var isLoading = false
    @State private var selectedImages: [UIImage] = []
    @State private var imageSelection: [PhotosPickerItem] = []
    @FocusState private var isTextEditorFocused: Bool
    
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
            ZStack {
                // Background
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with user profile
                    HStack(spacing: 12) {
                        if let profileImage = userService.currentUserProfile?.avatarURL {
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    )
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.gray)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
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
                            
                            // Show session indicator for session posts
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
                        
                        Spacer()
                    }
                    .padding()
                    
                    // Session display section
                    if isSessionPost && sessionId != nil {
                        // Choose the right session display based on content type
                        if showFullSessionCard {
                            // For notes/hands: full session card
                            SessionCard(text: extractSessionDetails())
                                .padding(.horizontal)
                                .padding(.bottom, 16)
                        } else {
                            // For stack updates: compact session badge
                            if let (gameName, stakes) = parseSessionInfo() {
                                SessionBadgeView(gameName: gameName, stakes: stakes)
                                    .padding(.horizontal)
                                    .padding(.bottom, 8)
                            } else {
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
                        }
                    }
                    
                    // Note view (only for note posts)
                    if isNote {
                        SharedNoteView(note: initialText)
                            .padding(.horizontal)
                    }
                    
                    // Hand Summary (only for hand posts)
                    if isHandPost, let handData = hand {
                        HandSummaryView(hand: handData)
                            .padding(.horizontal)
                    }
                    
                    // Text Editor (hide initial text for notes since it's displayed above)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $postText)
                            .focused($isTextEditorFocused)
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            .scrollContentBackground(.hidden)
                            .padding()
                            .background(Color.clear)
                        
                        if postText.isEmpty && !isTextEditorFocused {
                            Text(placeholderText)
                                .foregroundColor(Color.gray)
                                .font(.system(size: 16))
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Image picker and preview (only for regular posts)
                    if !isHandPost && !isNote {
                        VStack(spacing: 12) {
                            // Image picker button
                            PhotosPicker(selection: $imageSelection, maxSelectionCount: 4, matching: .images) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 16))
                                    Text("Add Photos")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 1.0)))
                                )
                            }
                            
                            // Selected images preview
                            if !selectedImages.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(0..<selectedImages.count, id: \.self) { index in
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
                                    }
                                    .padding(.top, 4)
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    
                    // Character count
                    HStack {
                        Spacer()
                        Text("\(280 - postText.count)")
                            .foregroundColor(postText.count > 280 ? .red : .gray)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: isHandPost ? shareHand : createPost) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isHandPost ? "Share" : "Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled((postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isNote && !showFullSessionCard) || isLoading || postText.count > 280 || userService.currentUserProfile == nil)
                    .foregroundColor((postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isNote && !showFullSessionCard) || postText.count > 280 || userService.currentUserProfile == nil ? .gray : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
            }
            .onChange(of: imageSelection) { _, newValue in
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
            .onAppear {
                if !initialText.isEmpty {
                    // For notes, we keep the initial text in the note view but clear it from the editor
                    if !isNote && !showFullSessionCard {
                        postText = initialText
                    }
                }
                isTextEditorFocused = true
                // Fetch user profile if not loaded
                if userService.currentUserProfile == nil {
                    Task {
                        try? await userService.fetchUserProfile()
                    }
                }
            }
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
    
    private var placeholderText: String {
        if isSessionPost {
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
        guard (postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (isNote || showFullSessionCard)) || !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let username = userService.currentUserProfile?.username else { return }
        
        let displayName = userService.currentUserProfile?.displayName
        let profileImage = userService.currentUserProfile?.avatarURL
        
        // Handle different content types:
        let content: String
        
        // For note posts with no additional comment
        if isNote && postText.isEmpty {
            content = initialText
        }
        // For note posts with a comment
        else if isNote && !postText.isEmpty {
            content = "\(postText)\n\nNote: \(initialText)"
        }
        // For chip updates (showing full session card)
        else if showFullSessionCard {
            if postText.isEmpty {
                // Just use the session details plus the content
                content = initialText
            } else {
                // Use the session details plus user comment
                content = initialText
            }
        }
        // Default case - regular post
        else {
            content = postText
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
        
        isLoading = true
        
        Task {
            do {
                try await postService.createHandPost(
                    content: postText,
                    userId: userId,
                    username: username,
                    displayName: displayName,
                    profileImage: profileImage,
                    hand: hand,
                    sessionId: sessionId
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
} 
