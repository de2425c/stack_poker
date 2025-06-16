import SwiftUI
import Kingfisher

struct PostView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    let userId: String
    var onImageTapped: ((String) -> Void)?
    @State private var showingReplay = false
    @State private var isLiked: Bool
    @State private var authorProfile: UserProfile?
    
    @EnvironmentObject private var userService: UserService
    
    init(post: Post, onLike: @escaping () -> Void, onComment: @escaping () -> Void, userId: String, onImageTapped: ((String) -> Void)? = nil) {
        self.post = post
        self.onLike = onLike
        self.onComment = onComment
        self.userId = userId
        self.onImageTapped = onImageTapped
        // Initialize isLiked from the post's state
        _isLiked = State(initialValue: post.isLiked)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Check if this is a challenge-related post first
            if let challengeInfo = extractChallengeInfo() {
                ChallengePostView(
                    post: post,
                    challengeInfo: challengeInfo,
                    onLike: onLike,
                    onComment: onComment,
                    isCurrentUser: post.userId == userId,
                    onImageTapped: onImageTapped,
                    openPostDetail: onComment
                )
            } else if post.postType == .text {
                BasicPostCardView(
                    post: post,
                    onLike: onLike,
                    onComment: onComment,
                    onDelete: {},
                    isCurrentUser: post.userId == userId,
                    onImageTapped: onImageTapped,
                    openPostDetail: onComment,
                    onReplay: post.postType == .hand ? { showingReplay = true } : nil
                )
            } else if post.postType == .hand {
                PostCardView(
                    post: post,
                    onLike: onLike,
                    onComment: onComment,
                    onDelete: {},
                    isCurrentUser: post.userId == userId,
                    userId: userId
                )
            }
        }
        .background(Color.clear) // Modified to be transparent
        .sheet(isPresented: $showingReplay) {
            if let hand = post.handHistory {
                HandReplayView(hand: hand, userId: userId)
            }
        }
        .onAppear {
            loadAuthorProfile()
        }
    }
    
    // MARK: - Challenge Detection
    
    private func extractChallengeInfo() -> ChallengePostInfo? {
        let content = post.content
        
        // Check for challenge completion posts FIRST (most specific)
        if content.contains("🎉 Challenge Completed!") || content.contains("🏆 Goal Achieved!") || content.contains("#ChallengeCompleted") {
            return parseChallengeCompletionPost(content)
        }
        
        // Check for challenge progress posts SECOND (before start posts to avoid confusion)
        if content.contains("Challenge Progress:") || content.contains("🎯 Challenge Update:") || content.contains("#ChallengeProgress") {
            return parseChallengeProgressPost(content)
        }
        
        // Check for challenge start posts LAST
        if content.contains("🎯 Started a new challenge:") && content.contains("#PokerChallenge") {
            return parseChallengeStartPost(content)
        }
        
        return nil
    }
    
    private func parseChallengeStartPost(_ content: String) -> ChallengePostInfo? {
        // Extract challenge title
        guard let titleRange = content.range(of: "Started a new challenge: "),
              let titleEnd = content.range(of: "\n", range: titleRange.upperBound..<content.endIndex) else {
            return nil
        }
        
        let title = String(content[titleRange.upperBound..<titleEnd.lowerBound])
        
        // Extract target and current values
        let targetValue = extractValue(from: content, prefix: "Target: ")
        let currentValue = extractValue(from: content, prefix: "Current: ")
        
        // Extract deadline if present
        let deadline = extractDeadline(from: content)
        
        // Provide default values if extraction fails
        let target = targetValue ?? 0.0
        let current = currentValue ?? 0.0
        
        // Determine challenge type from hashtags
        let challengeType: ChallengeType
        if content.contains("#BankrollGoal") {
            challengeType = .bankroll
        } else if content.contains("#HandsGoal") {
            challengeType = .hands
        } else if content.contains("#SessionGoal") {
            challengeType = .session
        } else {
            challengeType = .bankroll // Default
        }
        
        return ChallengePostInfo(
            type: .challengeStart,
            challengeTitle: title,
            challengeType: challengeType,
            currentValue: current,
            targetValue: target,
            progressPercentage: target > 0 ? (current / target) * 100 : 0,
            isCompact: false,
            deadline: deadline
        )
    }
    
    private func parseChallengeProgressPost(_ content: String) -> ChallengePostInfo? {
        // Extract challenge title from "🎯 Challenge Update: [Title]" format
        var challengeTitle = "Challenge Progress"
        if let titleRange = content.range(of: "🎯 Challenge Update: ") {
            let remainingContent = String(content[titleRange.upperBound...])
            if let titleEnd = remainingContent.range(of: "\n") {
                challengeTitle = String(remainingContent[..<titleEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Extract target and current values
        let targetValue = extractValue(from: content, prefix: "Target: ") ?? extractValue(from: content, prefix: "Goal: ")
        let currentValue = extractValue(from: content, prefix: "Current: ") ?? extractValue(from: content, prefix: "Progress: ")
        
        let deadline = extractDeadline(from: content)
        
        guard let target = targetValue, let current = currentValue else { return nil }
        
        // Determine challenge type from hashtags
        let challengeType: ChallengeType
        if content.contains("#BankrollGoal") {
            challengeType = .bankroll
        } else if content.contains("#HandsGoal") {
            challengeType = .hands
        } else if content.contains("#SessionGoal") {
            challengeType = .session
        } else {
            challengeType = .bankroll // Default
        }
        
        return ChallengePostInfo(
            type: .challengeProgress,
            challengeTitle: challengeTitle,
            challengeType: challengeType,
            currentValue: current,
            targetValue: target,
            progressPercentage: (current / target) * 100,
            isCompact: true,
            deadline: deadline
        )
    }
    
    private func parseChallengeCompletionPost(_ content: String) -> ChallengePostInfo? {
        // Extract challenge title - it's on the line after "🎉 Challenge Completed!"
        var challengeTitle = "Challenge Completed!"
        let lines = content.components(separatedBy: "\n")
        
        for (index, line) in lines.enumerated() {
            if line.contains("🎉 Challenge Completed!") && index + 2 < lines.count {
                // Title is 2 lines down (skipping the empty line)
                challengeTitle = lines[index + 2].trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        let targetValue = extractValue(from: content, prefix: "Target: ") ?? extractValue(from: content, prefix: "Goal: ")
        let currentValue = extractValue(from: content, prefix: "Final: ") ?? extractValue(from: content, prefix: "Achieved: ")
        
        let deadline = extractDeadline(from: content)
        
        guard let target = targetValue, let current = currentValue else { return nil }
        
        // Determine challenge type from hashtags
        let challengeType: ChallengeType
        if content.contains("#BankrollGoal") {
            challengeType = .bankroll
        } else if content.contains("#HandsGoal") {
            challengeType = .hands
        } else if content.contains("#SessionGoal") {
            challengeType = .session
        } else {
            challengeType = .bankroll // Default
        }
        
        return ChallengePostInfo(
            type: .challengeCompletion,
            challengeTitle: challengeTitle,
            challengeType: challengeType,
            currentValue: current,
            targetValue: target,
            progressPercentage: 100,
            isCompact: false,
            deadline: deadline
        )
    }
    
    private func extractValue(from content: String, prefix: String) -> Double? {
        guard let range = content.range(of: prefix) else { return nil }
        
        let remainingContent = String(content[range.upperBound...])
        let rawToken = remainingContent.components(separatedBy: CharacterSet.whitespacesAndNewlines).first ?? ""
        
        // Strip any characters that are NOT part of a standard number representation (digits or decimal separator)
        let numericToken = rawToken.filter { ("0123456789.").contains($0) }
        
        return Double(numericToken)
    }
    
    private func extractDeadline(from content: String) -> Date? {
        // Look for deadline in various formats
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("Deadline: ") {
                let dateString = line.replacingOccurrences(of: "Deadline: ", with: "")
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return formatter.date(from: dateString)
            }
        }
        return nil
    }
    
    private func loadAuthorProfile() {
        Task {
            if let profiles = try? await userService.fetchUserProfiles(byIds: [post.userId]), let profile = profiles.first {
                DispatchQueue.main.async {
                    self.authorProfile = profile
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    // Extract session info from content
    private func extractSessionInfo() -> (gameName: String, stakes: String)? {
        // First check for explicitly formatted session info
        if post.content.starts(with: "SESSION_INFO:") {
            let lines = post.content.components(separatedBy: "\n")
            if let firstLine = lines.first, firstLine.starts(with: "SESSION_INFO:") {
                let parts = firstLine.components(separatedBy: ":")
                if parts.count >= 3 {
                    let gameName = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let stakes = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    return (gameName, stakes)
                }
            }
        }
        
        // Try directly using sessionId if available
        if post.sessionId != nil {
            return ("Live Poker", "$1/$2")  // Fallback values
        }
        
        return nil
    }
    
    // Detect if post contains a note
    private var isNote: Bool {
        // Check for note in content after SESSION_INFO
        if post.content.starts(with: "SESSION_INFO:") {
            let contentWithoutSessionInfo = post.content.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            if contentWithoutSessionInfo.contains("\n\nNote: ") || contentWithoutSessionInfo.contains("Note: ") {
                return true
            }
        }
        
        // Regular note detection
        if post.content.contains("\n\nNote: ") || post.content.starts(with: "Note: ") {
            return true
        }
        
        return false
    }
    
    // Extract note content
    private var noteContent: String {
        // Handle SESSION_INFO format
        if post.content.starts(with: "SESSION_INFO:") {
            let contentWithoutSessionInfo = post.content.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
            
            if let range = contentWithoutSessionInfo.range(of: "Note: ") {
                return String(contentWithoutSessionInfo[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Regular extraction
        if let range = post.content.range(of: "Note: ") {
            return String(post.content[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return ""
    }
    
    // Extract comment content
    private var commentContent: String {
        // Handle SESSION_INFO format
        if post.content.starts(with: "SESSION_INFO:") {
            let lines = post.content.components(separatedBy: "\n")
            if lines.count > 1 {
                let contentWithoutSessionInfo = lines.dropFirst().joined(separator: "\n")
                
                if let range = contentWithoutSessionInfo.range(of: "\n\nNote:") {
                    return String(contentWithoutSessionInfo[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else if !contentWithoutSessionInfo.starts(with: "Note: ") {
                    return contentWithoutSessionInfo.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return ""
            }
        }
        
        // Regular extraction
        if let range = post.content.range(of: "\n\nNote:") {
            return String(post.content[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if !post.content.starts(with: "Note: ") {
            return post.content
        }
        
        return ""
    }
}

// MARK: - Completed Session Parsing

struct ParsedCompletedSessionInfo {
    let title: String
    let gameName: String
    let stakes: String
    let duration: String // Kept as string as it's pre-formatted
    let buyIn: String    // Kept as string
    let cashout: String  // Kept as string
    let profit: String   // Kept as string
    // Add other fields if necessary, e.g., location if you add it later
}

func parseCompletedSessionInfo(from content: String) -> (info: ParsedCompletedSessionInfo?, comment: String) {
    let prefix = "COMPLETED_SESSION_INFO:"
    guard content.starts(with: prefix) else {
        return (nil, content)
    }

    let contentWithoutPrefix = String(content.dropFirst(prefix.count))
    let lines = contentWithoutPrefix.components(separatedBy: "\n")
    
    guard let sessionDetailsLine = lines.first else {
        return (nil, content) 
    }
    
    // DEBUG: Print the line being parsed
    // print("DEBUG: Parsing sessionDetailsLine: '\(sessionDetailsLine)'")

    var title = "N/A"
    var gameName = "N/A"
    var stakes = "N/A"
    var duration = "N/A"
    var buyIn = "N/A"
    var cashout = "N/A"
    var profit = "N/A"

    let detailComponents = sessionDetailsLine.components(separatedBy: ", ")
    for component in detailComponents {
        let keyValue = component.components(separatedBy: ": ")
        if keyValue.count == 2 {
            let key = keyValue[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = keyValue[1].trimmingCharacters(in: .whitespacesAndNewlines)
            // DEBUG: Print each key-value pair
            // print("DEBUG: Key: '\(key)', Value: '\(value)'")
            switch key {
            case "Title": title = value
            case "Game": gameName = value
            case "Stakes": stakes = value
            case "Duration": duration = value
            case "Buy-in": buyIn = value
            case "Cashout": cashout = value
            case "Profit": profit = value
            default: 
                // print("DEBUG: Unknown key: \(key)")
                break
            }
        }
    }
    
    let parsedInfo = ParsedCompletedSessionInfo(title: title, gameName: gameName, stakes: stakes, duration: duration, buyIn: buyIn, cashout: cashout, profit: profit)
    
    let comment = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    
    return (parsedInfo, comment)
}

// MARK: - Support Views


struct HandSummaryView: View {
    let hand: ParsedHandHistory
    @State private var isHovered = false
    var onReplayTap: (() -> Void)? = nil
    var showReplayButton: Bool = true
    
    private var hero: Player? {
        hand.raw.players.first(where: { $0.isHero })
    }
    
    private var heroPnl: Double {
        hand.raw.pot.heroPnl ?? 0
    }
    
    private var formattedPnl: String {
        if heroPnl >= 0 {
            return "$\(Int(heroPnl))"
        } else {
            return "-$\(abs(Int(heroPnl)))"
        }
    }
    
    private var formattedStakes: String {
        let sb = hand.raw.gameInfo.smallBlind
        let bb = hand.raw.gameInfo.bigBlind
        return "$\(Int(sb))/$\(Int(bb))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Stakes and PnL
            HStack(alignment: .center) {
                // Stakes
                Text(formattedStakes)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 40/255, green: 40/255, blue: 45/255))
                    )
                
                Spacer()
                
                // PnL
                Text(formattedPnl)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(heroPnl >= 0 ? Color(red: 123/255, green: 255/255, blue: 99/255) : .red)
                    .shadow(color: heroPnl >= 0 ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.3) : .red.opacity(0.3), radius: 2)
            }
            
            // Middle row: Cards and Hand Strength
            HStack(alignment: .center, spacing: 12) {
                // Hero's Cards
                if let hero = hero, let cards = hero.cards {
                    HStack(spacing: 4) {
                        ForEach(cards, id: \.self) { card in
                            CardView(card: Card(from: card))
                                .aspectRatio(0.69, contentMode: .fit)
                                .frame(width: 36, height: 52)
                                .shadow(color: .black.opacity(0.2), radius: 2)
                        }
                    }
                }
                
                if let strength = hero?.finalHand {
                    Text(strength)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 45/255, green: 45/255, blue: 50/255))
                                .shadow(color: .black.opacity(0.1), radius: 1)
                        )
                }
                
                Spacer()
                
                // Replay button - only show if showReplayButton is true
                if showReplayButton {
                    Button(action: {
                        if let onReplayTap = onReplayTap {
                            onReplayTap()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                            Text("Replay")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        )
                        .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3)), radius: 2, y: 1)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 25/255, green: 25/255, blue: 30/255))
                .shadow(color: .black.opacity(0.1), radius: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

// Extension for Date to show relative time
extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Challenge Post Info

struct ChallengePostInfo {
    enum PostType {
        case challengeStart
        case challengeProgress
        case challengeCompletion
    }
    
    let type: PostType
    let challengeTitle: String
    let challengeType: ChallengeType
    let currentValue: Double
    let targetValue: Double
    let progressPercentage: Double
    let isCompact: Bool
    let deadline: Date?
    
    var daysRemaining: Int? {
        guard let deadline = deadline else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: Date(), to: deadline).day
        return max(days ?? 0, 0)
    }
}

// MARK: - Challenge Post View

struct ChallengePostView: View {
    let post: Post
    let challengeInfo: ChallengePostInfo
    let onLike: () -> Void
    let onComment: () -> Void
    let isCurrentUser: Bool
    var onImageTapped: ((String) -> Void)?
    var openPostDetail: (() -> Void)?
    
    @State private var isLiked: Bool
    @State private var animateLike = false
    @EnvironmentObject private var userService: UserService
    
    init(post: Post, challengeInfo: ChallengePostInfo, onLike: @escaping () -> Void, onComment: @escaping () -> Void, isCurrentUser: Bool, onImageTapped: ((String) -> Void)? = nil, openPostDetail: (() -> Void)? = nil) {
        self.post = post
        self.challengeInfo = challengeInfo
        self.onLike = onLike
        self.onComment = onComment
        self.isCurrentUser = isCurrentUser
        self.onImageTapped = onImageTapped
        self.openPostDetail = openPostDetail
        _isLiked = State(initialValue: post.isLiked)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Challenge context tag
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
                Text(challengeContextText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            // Header with user info
            HStack(alignment: .top, spacing: 10) {
                NavigationLink(destination: UserProfileView(userId: post.userId).environmentObject(userService)) {
                    Group {
                        if let profileImage = post.profileImage {
                            KFImage(URL(string: profileImage))
                                .placeholder {
                                    PlaceholderAvatarView(size: 40)
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        } else {
                            PlaceholderAvatarView(size: 40)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 4) {
                        Text(post.displayName ?? post.username)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            
                        Text("@\(post.username)")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.8))
                    }
                    
                    Text(post.createdAt.timeAgo())
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            // Post content (text before the challenge component)
            if !cleanedPostContent.isEmpty {
                Text(cleanedPostContent)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.95))
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
            
            // Challenge Progress Component
            ChallengeProgressComponent(
                challenge: Challenge(
                    userId: post.userId,
                    type: challengeInfo.challengeType,
                    title: challengeInfo.challengeTitle,
                    description: "", // Empty description for display purposes
                    targetValue: challengeInfo.targetValue,
                    currentValue: challengeInfo.currentValue,
                    endDate: challengeInfo.deadline
                ),
                isCompact: challengeInfo.isCompact
            )
            .padding(.horizontal, 16)
            
            // Deadline info if present
            if let daysRemaining = challengeInfo.daysRemaining {
                HStack {
                    Image(systemName: "calendar.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    if daysRemaining > 0 {
                        Text("\(daysRemaining) days left to complete")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)
                    } else if daysRemaining == 0 {
                        Text("Due today!")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    } else {
                        Text("Overdue")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                Spacer()
                    .frame(height: 12)
            }
            
            // Images if any
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageURLs, id: \.self) { url in
                            if let imageUrl = URL(string: url) {
                                KFImage(imageUrl)
                                    .placeholder {
                                        Rectangle()
                                            .fill(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 1.0)))
                                            .overlay(
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                                            )
                                    }
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 350)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onImageTapped?(url)
                                    }
                            }
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 8)
                }
                .padding(.top, 10)
                .padding(.bottom, 14)
            }
            
            // Actions bar
            HStack(spacing: 36) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        animateLike = true
                        isLiked.toggle()
                        onLike()
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            animateLike = false
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 16))
                            .foregroundColor(isLiked ? .red : .gray.opacity(0.7))
                            .scaleEffect(animateLike ? 1.3 : 1.0)
                        
                        Text("\(post.likes)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                
                Button(action: {
                    if let postDetailAction = openPostDetail {
                        postDetailAction()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16))
                            .foregroundColor(.gray.opacity(0.7))
                        
                        Text("\(post.comments)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.clear)
    }
    
    private var challengeContextText: String {
        switch challengeInfo.type {
        case .challengeStart:
            return "Challenge Started"
        case .challengeProgress:
            return "Challenge Update"
        case .challengeCompletion:
            return "Challenge Completed!"
        }
    }
    
    private var cleanedPostContent: String {
        var content = post.content
        
        // Remove challenge-specific formatting but keep the main message
        content = content.replacingOccurrences(of: "🎯 Started a new challenge:", with: "")
        content = content.replacingOccurrences(of: "🎯 Challenge Update:", with: "")
        content = content.replacingOccurrences(of: "🎉 Challenge Completed!", with: "")
        content = content.replacingOccurrences(of: "🏆 Goal Achieved!", with: "")
        
        // Split into lines and filter out technical lines
        let lines = content.components(separatedBy: "\n")
        let filteredLines = lines.filter { line in
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !line.contains("Target:") &&
            !line.contains("Current:") &&
            !line.contains("Goal:") &&
            !line.contains("Progress:") &&
            !line.contains("Final:") &&
            !line.contains("Achieved:") &&
            !line.contains("Total Hours:") &&
            !line.contains("Sessions:") &&
            !line.contains("% Complete") &&
            !line.hasPrefix("#") &&
            !line.contains("Deadline:") &&
            trimmedLine != challengeInfo.challengeTitle &&
            !trimmedLine.isEmpty
        }
        
        return filteredLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

