import SwiftUI
import Kingfisher

struct PostView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    let userId: String
    @State private var showingReplay = false
    @State private var isLiked: Bool
    @State private var authorProfile: UserProfile?
    
    @EnvironmentObject private var userService: UserService
    
    init(post: Post, onLike: @escaping () -> Void, onComment: @escaping () -> Void, userId: String) {
        self.post = post
        self.onLike = onLike
        self.onComment = onComment
        self.userId = userId
        // Initialize isLiked from the post's state
        _isLiked = State(initialValue: post.isLiked)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if post.postType == .text {
                BasicPostCardView(
                    post: post,
                    onLike: onLike,
                    onComment: onComment,
                    onDelete: {},
                    isCurrentUser: post.userId == userId,
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

