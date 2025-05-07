import SwiftUI

struct PostView: View {
    let post: Post
    let onLike: () -> Void
    let onComment: () -> Void
    @State private var showingReplay = false
    @State private var isLiked = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AppBackgroundView()
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
                    Text(post.content)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
        .sheet(isPresented: $showingReplay) {
            if let hand = post.handHistory {
                HandReplayView(hand: hand)
            }
        }
    }
}

struct HandSummaryView: View {
    let hand: ParsedHandHistory
    @State private var isHovered = false
    var onReplayTap: (() -> Void)? = nil
    
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
            return "$\(abs(Int(heroPnl)))"
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
                
                // Replay button
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