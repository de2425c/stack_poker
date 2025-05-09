import SwiftUI

struct PostView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    let userId: String
    @State private var showingReplay = false
    @State private var isLiked = false
    
    var body: some View {
        ZStack {
            // Use the AppBackgroundView as a background
            AppBackgroundView(edges: .none)
            
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let profileImage = post.profileImage {
                        AsyncImage(url: URL(string: profileImage)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                        }
                    } else {
                        Circle()
                            .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                
                // Content
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack(spacing: 6) {
                        Text(post.username)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        
                        // Session badge for posts from sessions
                        if post.sessionId != nil {
                            sessionBadge
                        }
                        
                        Text("·")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray.opacity(0.7))
                        
                        Text(post.createdAt.timeAgo())
                            .font(.system(size: 15))
                            .foregroundColor(.gray.opacity(0.7))
                        
                        Spacer(minLength: 0)
                    }
                    
                    // Post content
                    if !post.content.isEmpty {
                        postContentView
                    }
                    
                    // Hand post content
                    if post.postType == .hand, let hand = post.handHistory {
                        HandSummaryView(hand: hand)
                    }
                    
                    // Images
                    if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(imageURLs, id: \.self) { url in
                                    AsyncImage(url: URL(string: url)) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        Rectangle()
                                            .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                    }
                                    .frame(width: 200, height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    
                    // Actions
                    HStack(spacing: 32) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isLiked.toggle()
                                onLike()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .font(.system(size: 16))
                                    .foregroundColor(isLiked ? .red : .gray.opacity(0.7))
                                Text("\(post.likes)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                        
                        Button(action: onComment) {
                            HStack(spacing: 6) {
                                Image(systemName: "message")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray.opacity(0.7))
                                Text("\(post.comments)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
            .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
        }
        .sheet(isPresented: $showingReplay) {
            if let hand = post.handHistory {
                HandReplayView(hand: hand, userId: userId)
            }
        }
    }
    
    // MARK: - Session Badge
    private var sessionBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 10))
            Text("Session")
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                .overlay(
                    Capsule()
                        .stroke(Color(red: 123/255, green: 255/255, blue: 99/255), lineWidth: 1)
                )
        )
        .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
    }
    
    // MARK: - Computed Properties
    
    // Extracted post content view to avoid complex control flow in ViewBuilder
    private var postContentView: some View {
        Group {
            if post.sessionId != nil {
                sessionPostContent
            } else {
                // Regular post content
                Text(post.content)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Session Content Views
    
    private struct ParsedSessionContent {
        let gameName: String
        let stakes: String
        let chipAmount: Double
        let buyIn: Double
        let elapsedTime: TimeInterval
        let actualContent: String
    }
    
    private struct SessionContentView: View {
        let parsedContent: ParsedSessionContent
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                // Use the new eye-catching LiveSessionStatusView
                LiveSessionStatusView(
                    gameName: parsedContent.gameName,
                    stakes: parsedContent.stakes,
                    chipAmount: parsedContent.chipAmount,
                    buyIn: parsedContent.buyIn,
                    elapsedTime: parsedContent.elapsedTime,
                    isLive: true  // Assume active when shown in feed
                )
                
                if !parsedContent.actualContent.isEmpty {
                    Text(parsedContent.actualContent)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
    }
    
    // Session post content processing
    private var sessionPostContent: some View {
        Group {
            if let parsed = parseSessionContent() {
                SessionContentView(parsedContent: parsed)
            } else {
                Text(post.content)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    // MARK: - Parsing Methods
    
    private func parseSessionContent() -> ParsedSessionContent? {
        // Split by lines and trim whitespace
        let rawLines = post.content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard rawLines.count >= 3 else { return nil }
        
        // Attempt to identify summary lines (order may vary slightly if user edited)
        var gameLine: String?
        var stackLine: String?
        var timeLine: String?
        var remainingLines: [String] = []
        
        for line in rawLines {
            if line.hasPrefix("Session at ") { gameLine = line; continue }
            if line.hasPrefix("Stack:") { stackLine = line; continue }
            if line.hasPrefix("Time:") { timeLine = line; continue }
            remainingLines.append(line)
        }
        guard let gLine = gameLine, let sLine = stackLine, let tLine = timeLine else { return nil }
        
        let (gameName, stakes) = parseGameAndStakes(from: gLine)
        let (chipAmount, buyIn) = parseStackInfo(from: sLine)
        let elapsedTime = parseSessionTime(from: tLine)
        let actualContent = remainingLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        
        return ParsedSessionContent(gameName: gameName, stakes: stakes, chipAmount: chipAmount, buyIn: buyIn, elapsedTime: elapsedTime, actualContent: actualContent)
    }
    
    // Helper methods for parsing session details
    private func parseGameAndStakes(from line: String) -> (String, String) {
        var gameName = "Cash Game"
        var stakes = "$1/$2"
        
        if line.hasPrefix("Session at ") {
            let parts = line.dropFirst("Session at ".count).split(separator: "(")
            if parts.count >= 2 {
                gameName = String(parts[0]).trimmingCharacters(in: .whitespaces)
                stakes = String(parts[1]).replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        return (gameName, stakes)
    }
    
    private func parseStackInfo(from line: String) -> (Double, Double) {
        var chipAmount: Double = 0
        var buyIn: Double = 0
        
        if let stackMatch = line.range(of: "Stack: \\$([0-9]+)", options: .regularExpression) {
            let stackStr = String(line[stackMatch]).replacingOccurrences(of: "Stack: $", with: "")
            chipAmount = Double(stackStr) ?? 0
        }
        
        // Calculate buy-in based on profit
        if let profitMatch = line.range(of: "\\(([+-]\\$[0-9]+)\\)", options: .regularExpression) {
            let profitStr = String(line[profitMatch])
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "$", with: "")
            
            if let profit = Double(profitStr.replacingOccurrences(of: "+", with: "")) {
                buyIn = chipAmount - profit
            }
        }
        
        return (chipAmount, buyIn)
    }
    
    private func parseSessionTime(from line: String) -> TimeInterval {
        var elapsedTime: TimeInterval = 0
        
        if let timeMatch = line.range(of: "Time: ([0-9]+)h ([0-9]+)m", options: .regularExpression) {
            let timeStr = String(line[timeMatch]).replacingOccurrences(of: "Time: ", with: "")
            let timeParts = timeStr.split(separator: "h ")
            if timeParts.count >= 2 {
                let hours = Int(String(timeParts[0])) ?? 0
                let minutes = Int(String(timeParts[1]).replacingOccurrences(of: "m", with: "")) ?? 0
                elapsedTime = TimeInterval(hours * 3600 + minutes * 60)
            }
        }
        
        return elapsedTime
    }
}

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
