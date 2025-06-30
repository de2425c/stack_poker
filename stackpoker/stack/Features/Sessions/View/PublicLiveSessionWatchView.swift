import SwiftUI
import FirebaseFirestore
import Kingfisher

struct PublicLiveSessionWatchView: View {
    let sessionId: String
    let currentUserId: String
    
    @StateObject private var publicSessionService = PublicSessionService()
    @EnvironmentObject var userService: UserService
    
    @State private var session: PublicLiveSession?
    @State private var isLoading = true
    @State private var comments: [LiveComment] = []
    @State private var newCommentText = ""
    @State private var isSubmittingComment = false
    @State private var timer: Timer?
    @State private var keyboardHeight: CGFloat = 0
    
    private var isSessionOwner: Bool {
        session?.userId == currentUserId
    }
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            if isLoading {
                loadingView
            } else if let session = session {
                liveSessionContent(session: session)
            } else {
                errorView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
                keyboardHeight = keyboardFrame.cgRectValue.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onAppear {
            startListening()
            startDurationTimer()
        }
        .onDisappear {
            stopListening()
            stopDurationTimer()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Loading Live Session...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Error View
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("Session Not Found")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            
            Text("This session may have ended or been removed.")
                .font(.system(size: 14))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // MARK: - Live Session Content
    private func liveSessionContent(session: PublicLiveSession) -> some View {
        VStack(spacing: 0) {
            // Live Status Indicator
            HStack {
                Spacer()
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .scaleEffect(session.isLive ? 1.0 : 0.5)
                        .animation(
                            session.isLive ? 
                            Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) : 
                            .default,
                            value: session.isLive
                        )
                    
                    Text(session.isLive ? "LIVE" : "ENDED")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(session.isLive ? .red : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .stroke(session.isLive ? Color.red.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
                )
                
                Spacer()
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)
            
            ScrollView {
                VStack(spacing: 24) {
                    // Session Header
                    sessionHeaderView(session: session)
                    
                    // Show different content based on session status
                    if session.isLive {
                        // Live Stats
                        liveStatsView(session: session)
                        
                        // Live Chat (now includes comment input)
                        liveChatView(session: session)
                    } else {
                        // Session Recap - simplified for finished sessions
                        sessionRecapView(session: session)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, keyboardHeight > 0 ? 20 : 100)
            }
        }
    }
    
    // MARK: - Session Header
    private func sessionHeaderView(session: PublicLiveSession) -> some View {
        VStack(spacing: 20) {
            // User Info
            HStack(spacing: 16) {
                // Profile picture
                NavigationLink(destination: UserProfileView(userId: session.userId).environmentObject(userService)) {
                    Group {
                        if !session.userProfileImageURL.isEmpty, let url = URL(string: session.userProfileImageURL) {
                            KFImage(url)
                                .placeholder {
                                    PlaceholderAvatarView(size: 60)
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } else {
                            PlaceholderAvatarView(size: 60)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.userName)
                        .font(.plusJakarta(.title2, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Started \(session.startTime.timeAgo())")
                        .font(.plusJakarta(.subheadline))
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            
            // Game Info Card
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(session.sessionType.lowercased() == "tournament" ? "Tournament Session" : "Cash Game Session")
                        .font(.plusJakarta(.caption, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    Spacer()
                }
                
                Text(gameDisplayText(session: session))
                    .font(.plusJakarta(.headline, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Live Stats
    private func liveStatsView(session: PublicLiveSession) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Live Stats")
                    .font(.plusJakarta(.title2, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            // Tournament vs Cash Game Stats
            if session.sessionType.lowercased() == "tournament" {
                tournamentStatsGrid(session: session)
            } else {
                cashGameStatsGrid(session: session)
            }
        }
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(session.isLive ? Color.red.opacity(0.2) : Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // Tournament Stats Grid
    private func tournamentStatsGrid(session: PublicLiveSession) -> some View {
        VStack(spacing: 16) {
            // First Row: Buy-in and Starting Chips
            HStack(spacing: 0) {
                StatColumnView(
                    title: "BUY-IN",
                    value: "$\(Int(session.buyIn))",
                    valueColor: .white
                )
                
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.1))
                
                StatColumnView(
                    title: "STARTING CHIPS",
                    value: session.startingChips != nil ? "\(Int(session.startingChips!))" : "20,000",
                    valueColor: .white
                )
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Second Row: Current Stack and Duration
            HStack(spacing: 0) {
                StatColumnView(
                    title: "CURRENT CHIPS",
                    value: "\(Int(session.currentStack))",
                    valueColor: .white
                )
                
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.1))
                
                StatColumnView(
                    title: "DURATION",
                    value: session.formattedDuration,
                    valueColor: .white
                )
            }
        }
    }
    
    // Cash Game Stats Grid
    private func cashGameStatsGrid(session: PublicLiveSession) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            StatCardView(
                title: "BUY-IN",
                value: "$\(Int(session.buyIn))",
                valueColor: .white
            )
            
            StatCardView(
                title: "CURRENT",
                value: "$\(Int(session.currentStack))",
                valueColor: .white
            )
            
            StatCardView(
                title: "PROFIT/LOSS",
                value: session.formattedProfit,
                valueColor: Color(session.profitColor)
            )
            
            StatCardView(
                title: "DURATION",
                value: session.formattedDuration,
                valueColor: .white
            )
        }
    }
    
    // MARK: - Session Recap (for finished sessions)
    private func sessionRecapView(session: PublicLiveSession) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Session Recap")
                    .font(.plusJakarta(.title2, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            // Simple recap stats
            if session.sessionType.lowercased() == "tournament" {
                tournamentRecapGrid(session: session)
            } else {
                cashGameRecapGrid(session: session)
            }
        }
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // Tournament Recap Grid (simplified)
    private func tournamentRecapGrid(session: PublicLiveSession) -> some View {
        HStack(spacing: 0) {
            // Buy-in
            StatColumnView(
                title: "BUY-IN",
                value: "$\(Int(session.buyIn))",
                valueColor: .white
            )
            
            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
            
            // Cash Out
            StatColumnView(
                title: "CASH OUT",
                value: "$\(Int(session.currentStack))",
                valueColor: .white
            )
            
            Divider()
                .frame(height: 40)
                .background(Color.white.opacity(0.1))
            
            // Duration
            StatColumnView(
                title: "DURATION",
                value: session.formattedDuration,
                valueColor: .white
            )
        }
    }
    
    // Cash Game Recap Grid (simplified)
    private func cashGameRecapGrid(session: PublicLiveSession) -> some View {
        VStack(spacing: 16) {
            // Buy-in and Cash Out
            HStack(spacing: 0) {
                StatColumnView(
                    title: "BUY-IN",
                    value: "$\(Int(session.buyIn))",
                    valueColor: .white
                )
                
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.1))
                
                StatColumnView(
                    title: "CASH OUT",
                    value: "$\(Int(session.currentStack))",
                    valueColor: .white
                )
            }
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Duration (centered)
            StatColumnView(
                title: "DURATION",
                value: session.formattedDuration,
                valueColor: .white
            )
        }
    }
    
    // MARK: - Live Chat with integrated input
    private func liveChatView(session: PublicLiveSession) -> some View {
        VStack(spacing: 20) {
            HStack {
                Text("Live Chat")
                    .font(.plusJakarta(.title2, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(comments.count) message\(comments.count == 1 ? "" : "s")")
                    .font(.plusJakarta(.caption))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
            
            // Scrollable chat area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if comments.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 32))
                                    .foregroundColor(.gray.opacity(0.5))
                                
                                Text("No messages yet")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(.white)
                                
                                Text("Be the first to comment!")
                                    .font(.plusJakarta(.subheadline))
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 32)
                        } else {
                            ForEach(comments) { comment in
                                LiveCommentView(
                                    comment: comment,
                                    isSessionOwner: comment.userId == session.userId
                                )
                                .id(comment.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(minHeight: 200, maxHeight: 300)
                .onChange(of: comments.count) { _ in
                    if let lastComment = comments.last {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lastComment.id, anchor: .bottom)
                        }
                    }
                }
                
                // Comment Input - now inside chat
                if session.isLive {
                    commentInputView()
                        .padding(.top, 16)
                }
            }
        }
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Comment Input
    private func commentInputView() -> some View {
        HStack(spacing: 12) {
            TextField("Add a comment...", text: $newCommentText)
                .font(.plusJakarta(.body))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            
            Button(action: submitComment) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 
                                  Color.gray.opacity(0.2) : 
                                  Color.blue)
                    )
            }
            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingComment)
        }
    }
    
    // MARK: - Helper Functions
    
    private func gameDisplayText(session: PublicLiveSession) -> String {
        if session.sessionType.lowercased() == "tournament" {
            if !session.casino.isEmpty {
                return "\(session.gameName) at \(session.casino)"
            } else {
                return session.gameName
            }
        } else {
            if !session.gameName.isEmpty && !session.stakes.isEmpty {
                return "\(session.gameName) (\(session.stakes))"
            } else if !session.stakes.isEmpty {
                return session.stakes
            } else if !session.gameName.isEmpty {
                return session.gameName
            } else {
                return "Cash Game"
            }
        }
    }
    
    private func startListening() {
        Task {
            do {
                // Load initial session data
                session = try await publicSessionService.getSession(id: sessionId)
                isLoading = false
                
                // Load comments
                try await loadComments()
                
                // Start real-time listeners
                startSessionListener()
                startCommentsListener()
            } catch {
                print("❌ Error loading session: \(error)")
                isLoading = false
            }
        }
    }
    
    private func stopListening() {
        // Stop listeners when view disappears
    }
    
    private func startDurationTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            // Refresh session data every 30 seconds to update duration
            Task {
                do {
                    if let updatedSession = try await publicSessionService.getSession(id: sessionId) {
                        await MainActor.run {
                            self.session = updatedSession
                        }
                    }
                } catch {
                    print("❌ Error refreshing session: \(error)")
                }
            }
        }
    }
    
    private func stopDurationTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func startSessionListener() {
        Firestore.firestore().collection("public_sessions").document(sessionId)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error listening to session updates: \(error)")
                    return
                }
                
                guard let document = snapshot,
                      document.exists,
                      let data = document.data() else { return }
                
                let updatedSession = PublicLiveSession(id: document.documentID, document: data)
                
                Task { @MainActor in
                    self.session = updatedSession
                }
            }
    }
    
    private func startCommentsListener() {
        Firestore.firestore().collection("public_sessions").document(sessionId)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("❌ Error listening to comments: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                let newComments = documents.compactMap { LiveComment(document: $0) }
                
                Task { @MainActor in
                    self.comments = newComments
                }
            }
    }
    
    private func loadComments() async throws {
        let snapshot = try await Firestore.firestore().collection("public_sessions").document(sessionId)
            .collection("comments")
            .order(by: "timestamp", descending: false)
            .getDocuments()
        
        let loadedComments = snapshot.documents.compactMap { LiveComment(document: $0) }
        
        await MainActor.run {
            self.comments = loadedComments
        }
    }
    
    private func submitComment() {
        let commentText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commentText.isEmpty, !isSubmittingComment else { return }
        
        isSubmittingComment = true
        
        let commentData: [String: Any] = [
            "userId": currentUserId,
            "userName": userService.currentUserProfile?.displayName ?? "Unknown",
            "userAvatarURL": userService.currentUserProfile?.avatarURL ?? "",
            "content": commentText,
            "timestamp": Timestamp(date: Date())
        ]
        
        Task {
            do {
                try await Firestore.firestore().collection("public_sessions").document(sessionId)
                    .collection("comments").addDocument(data: commentData)
                
                await MainActor.run {
                    self.newCommentText = ""
                    self.isSubmittingComment = false
                }
            } catch {
                print("❌ Error submitting comment: \(error)")
                await MainActor.run {
                    self.isSubmittingComment = false
                }
            }
        }
    }
}

// MARK: - Live Comment Model
struct LiveComment: Identifiable {
    let id: String
    let userId: String
    let userName: String
    let userAvatarURL: String
    let content: String
    let timestamp: Date
    
    init?(document: QueryDocumentSnapshot) {
        let data = document.data()
        
        self.id = document.documentID
        self.userId = data["userId"] as? String ?? ""
        self.userName = data["userName"] as? String ?? "Unknown"
        self.userAvatarURL = data["userAvatarURL"] as? String ?? ""
        self.content = data["content"] as? String ?? ""
        
        if let timestamp = data["timestamp"] as? Timestamp {
            self.timestamp = timestamp.dateValue()
        } else {
            return nil
        }
    }
}

// MARK: - Live Comment View
struct LiveCommentView: View {
    let comment: LiveComment
    let isSessionOwner: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Group {
                if !comment.userAvatarURL.isEmpty, let url = URL(string: comment.userAvatarURL) {
                    KFImage(url)
                        .placeholder {
                            PlaceholderAvatarView(size: 36)
                        }
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    PlaceholderAvatarView(size: 36)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(comment.userName)
                        .font(.plusJakarta(.subheadline, weight: isSessionOwner ? .bold : .semibold))
                        .foregroundColor(isSessionOwner ? .yellow : .white)
                    
                    Spacer()
                    
                    Text(comment.timestamp.timeAgo())
                        .font(.plusJakarta(.caption))
                        .foregroundColor(.gray.opacity(0.6))
                }
                
                Text(comment.content)
                    .font(.plusJakarta(.subheadline))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(nil)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Stat Components
private struct StatColumnView: View {
    let title: String
    let value: String
    let valueColor: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.plusJakarta(.caption, weight: .medium))
                .foregroundColor(.gray.opacity(0.8))
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(value)
                .font(.plusJakarta(.title3, weight: .bold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatCardView: View {
    let title: String
    let value: String
    let valueColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.plusJakarta(.caption2, weight: .medium))
                .foregroundColor(.gray.opacity(0.8))
                .textCase(.uppercase)
                .tracking(0.5)
            
            Text(value)
                .font(.plusJakarta(.headline, weight: .bold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }
} 