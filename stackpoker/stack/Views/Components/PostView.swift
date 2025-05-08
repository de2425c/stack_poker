import SwiftUI
import Kingfisher
import Foundation

// Type alias for the Hand model
typealias Hand = ParsedHandHistory

// Extension to provide the 'hand' property on Post
extension Post {
    var hand: ParsedHandHistory? {
        return handHistory
    }
}

struct PostView: View {
    let post: Post
    var onLike: (() -> Void)?
    var onComment: (() -> Void)?
    var onDelete: (() -> Void)?
    var isCurrentUser: Bool = false
    var shouldShowReplayButton: Bool = true
    
    @State private var isShowingImage = false
    @State private var selectedImageURL: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with user info
            HStack(spacing: 12) {
                // Enhanced profile image with glow effect
                KFImage(URL(string: post.profileImage ?? ""))
                    .placeholder {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .foregroundColor(.gray.opacity(0.7))
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.2), radius: 4, x: 0, y: 0)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.username)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(post.createdAt.timeAgo())
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if isCurrentUser {
                    Button(action: {
                        onDelete?()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray.opacity(0.9))
                            .frame(width: 30, height: 30)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.3))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                                    )
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Post content with enhanced spacing
            if !post.content.isEmpty {
                Text(post.content)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, post.handHistory != nil || !(post.imageURLs?.isEmpty ?? true) ? 12 : 16)
            }
            
            // Hand summary with enhanced visuals
            if let hand = post.hand {
                HandSummaryView(hand: hand, isHovered: false, onReplay: nil, showReplayButton: shouldShowReplayButton)
                    .padding(.horizontal, 16)
                    .padding(.bottom, post.imageURLs?.isEmpty ?? true ? 16 : 12)
                    .background(
                        // Subtle highlight behind hand summary
                        RoundedRectangle(cornerRadius: 0)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 30/255, green: 40/255, blue: 50/255).opacity(0.2),
                                        Color(red: 20/255, green: 30/255, blue: 40/255).opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.horizontal, 8)
                    )
            }
            
            // Images with improved layout
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                ImagesGalleryViews(urls: imageURLs, onTap: { url in
                    selectedImageURL = url
                    isShowingImage = true
                })
                .frame(maxHeight: 300)
                .padding(.bottom, 16)
            }
            
            // Action buttons with enhanced styling
            HStack(spacing: 24) {
                // Like button
                Button(action: {
                    onLike?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 18))
                            .foregroundColor(post.isLiked ? Color(red: 255/255, green: 100/255, blue: 100/255) : .white.opacity(0.85))
                        
                        Text("\(post.likes)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                
                // Comment button
                Button(action: {
                    onComment?()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.85))
                        
                        Text("\(post.comments)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            // Beautiful glass effect background for the entire post
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.black.opacity(0.25))
                .background(
                    // Subtle gradient overlay
                    LinearGradient(
                        colors: [
                            Color(red: 30/255, green: 30/255, blue: 40/255).opacity(0.4),
                            Color(red: 15/255, green: 15/255, blue: 25/255).opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .blendMode(.overlay)
                )
                .overlay(
                    // Subtle border
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.05),
                                    Color.clear,
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .fullScreenCover(isPresented: $isShowingImage) {
            if let url = selectedImageURL, let imageURL = URL(string: url) {
                ZStack {
                    // Dark background with AppBackgroundView
                    AppBackgroundView(edges: .all)
                    
                    VStack {
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                isShowingImage = false
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .padding()
                        }
                        
                        Spacer()
                        
                        KFImage(imageURL)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.black.opacity(0.3))
                        
                        Spacer()
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}

// Enhanced HandSummaryView with better visuals
struct HandSummaryView: View {
    let hand: Hand
    let isHovered: Bool
    var onReplay: (() -> Void)?
    var showReplayButton: Bool = true
    
    var heroPlayer: Player? {
        hand.raw.players.first { $0.isHero }
    }
    
    var heroPnL: Int {
        if let hero = heroPlayer {
            return Int(hand.raw.pot.heroPnl)
        }
        return 0
    }
    
    var formattedStakes: String {
        let smallBlind = hand.raw.gameInfo.smallBlind
        let bigBlind = hand.raw.gameInfo.bigBlind
        return "$\(Int(smallBlind))/$\(Int(bigBlind))"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Stakes with enhanced style
                Text(formattedStakes)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        // Break complex expression into parts
                        createStakesBackground()
                    )
                
                Spacer()
                
                // Enhanced profit/loss display
                if heroPnL != 0 {
                    HStack(spacing: 3) {
                        // Simplify by creating intermediate variables
                        let isProfitable = heroPnL > 0
                        let profitColor = Color(red: 100/255, green: 255/255, blue: 100/255)
                        let lossColor = Color(red: 255/255, green: 100/255, blue: 100/255)
                        let displayColor = isProfitable ? profitColor : lossColor
                        let iconName = isProfitable ? "arrow.up" : "arrow.down"
                        let amountText = isProfitable ? "$\(heroPnL)" : "$\(abs(heroPnL))"
                        
                        Image(systemName: iconName)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(displayColor)
                        
                        Text(amountText)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(displayColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        createProfitLossBackground()
                    )
                }
            }
            
            // Enhanced cards display
            if let heroPlayer = heroPlayer, let cards = heroPlayer.cards, cards.count >= 2 {
                HStack(spacing: 16) {
                    // Hero's hand
                    HStack(spacing: -10) {
                        // Fix the problematic ForEach by simplifying it
                        let cardIndices = Array(cards.prefix(2).indices) // Get only the first two cards
                        ForEach(cardIndices, id: \.self) { index in
                            // Create Card object from string
                            let cardObj = Card(from: cards[index])
                            CardView(card: cardObj)
                                .frame(width: 50, height: 70)
                                .shadow(color: Color.black.opacity(0.3), radius: 3, x: 0, y: 2)
                        }
                    }
                    .padding(.trailing, 4)
                    
                    // Hand strength or result
                    if let handStrength = heroPlayer.finalHand {
                        Text(handStrength)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Spacer()
                    
                    // Replay button with enhanced styling
                    if showReplayButton {
                        Button(action: {
                            onReplay?()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 12, weight: .bold))
                                
                                Text("Replay")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                createReplayButtonBackground()
                            )
                            .shadow(color: Color(red: 123/255, green: 255/255, blue: 99/255, opacity: 0.3), radius: 5, x: 0, y: 2)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            createHandSummaryBackground()
        )
    }
    
    // Helper method to create the background for stakes display
    private func createStakesBackground() -> some View {
        let gradientColors = [
            Color(red: 40/255, green: 40/255, blue: 60/255),
            Color(red: 30/255, green: 30/255, blue: 50/255)
        ]
        
        let gradient = LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        let borderColor = Color.white.opacity(0.15)
        
        return RoundedRectangle(cornerRadius: 4)
            .fill(gradient)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(borderColor, lineWidth: 0.5)
            )
    }
    
    // Helper method for profit/loss display background
    private func createProfitLossBackground() -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.black.opacity(0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
    
    // Helper method for replay button background
    private func createReplayButtonBackground() -> some View {
        let gradientColors = [
            Color(red: 123/255, green: 255/255, blue: 99/255),
            Color(red: 150/255, green: 255/255, blue: 120/255)
        ]
        
        let gradient = LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        return RoundedRectangle(cornerRadius: 6)
            .fill(gradient)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
    }
    
    // Helper method for the main HandSummaryView background
    private func createHandSummaryBackground() -> some View {
        let gradientColors = [
            Color(red: 25/255, green: 30/255, blue: 40/255),
            Color(red: 20/255, green: 25/255, blue: 35/255)
        ]
        
        let gradient = LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        let borderGradient = LinearGradient(
            colors: [
                Color.white.opacity(0.15),
                Color.white.opacity(0.05),
                Color.clear,
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        return RoundedRectangle(cornerRadius: 8)
            .fill(gradient)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderGradient, lineWidth: 1)
            )
    }
}

// Image Gallery View
struct ImagesGalleryViews: View {
    let urls: [String]
    let onTap: (String) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(urls, id: \.self) { urlString in
                    if let url = URL(string: urlString) {
                        KFImage(url)
                            .placeholder {
                                ZStack {
                                    Rectangle()
                                        .fill(Color(UIColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 1.0)))
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                }
                            }
                            .resizable()
                            .scaledToFill()
                            .frame(width: 200, height: 200)
                            .clipShape(Rectangle())
                            .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onTap(urlString)
                            }
                    }
                }
            }
        }
    }
}

// Helper for relative time display
extension Date {
    func timeAgo() -> String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.minute, .hour, .day, .weekOfMonth, .month, .year], from: self, to: now)
        
        if let years = components.year, years > 0 {
            return years == 1 ? "1y ago" : "\(years)y ago"
        }
        
        if let months = components.month, months > 0 {
            return months == 1 ? "1mo ago" : "\(months)mo ago"
        }
        
        if let weeks = components.weekOfMonth, weeks > 0 {
            return weeks == 1 ? "1w ago" : "\(weeks)w ago"
        }
        
        if let days = components.day, days > 0 {
            return days == 1 ? "1d ago" : "\(days)d ago"
        }
        
        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1h ago" : "\(hours)h ago"
        }
        
        if let minutes = components.minute, minutes > 0 {
            return minutes == 1 ? "1m ago" : "\(minutes)m ago"
        }
        
        return "just now"
    }
} 
