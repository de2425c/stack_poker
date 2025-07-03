import SwiftUI
import Kingfisher
import FirebaseFirestore

struct PublicLiveSessionCard: View {
    let session: PublicLiveSession
    let currentUserId: String
    let onViewTapped: () -> Void
    
    @EnvironmentObject var userService: UserService
    @State private var showingWatchView = false
    
    private var isOwnSession: Bool {
        return session.userId == currentUserId
    }
    
    private var gameDisplayText: String {
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with user info and live status
            HStack(alignment: .top, spacing: 12) {
                // Profile picture - tappable to navigate to user profile
                NavigationLink(destination: UserProfileView(userId: session.userId).environmentObject(userService)) {
                    Group {
                        if !session.userProfileImageURL.isEmpty, let url = URL(string: session.userProfileImageURL) {
                            KFImage(url)
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
                .buttonStyle(PlainButtonStyle())
                
                // User info and session details
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(session.userName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                        
                        // Live/Finished status badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(session.isLive ? Color.red : Color.gray)
                                .frame(width: 6, height: 6)
                            
                            Text(session.isLive ? "LIVE" : "FINISHED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(session.isLive ? Color.red : Color.gray)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(session.isLive ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                        )
                        
                        Spacer()
                    }
                    
                    Text(session.createdAt.timeAgo())
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.6))
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
            
            // Session content card
            VStack(spacing: 0) {
                // Game info header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.sessionType.lowercased() == "tournament" ? "Tournament Session" : "Cash Game Session")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.gray.opacity(0.8))
                            .textCase(.uppercase)
                        
                        Text(gameDisplayText)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    if session.isLive {
                        // Live session indicator
                        VStack(spacing: 2) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .scaleEffect(1.0)
                                .animation(
                                    Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                    value: session.isLive
                                )
                            
                            Text("LIVE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                // Stats section
                HStack(spacing: 0) {
                    if session.sessionType.lowercased() == "tournament" {
                        // Tournament stats
                        // Buy-in
                        StatColumnView(
                            title: "BUY-IN",
                            value: "$\(Int(session.buyIn))",
                            valueColor: .white
                        )
                        
                        Divider()
                            .frame(height: 30)
                            .background(Color.white.opacity(0.1))
                        
                        if session.isLive {
                            // Active tournament: show starting chips and current chips
                            StatColumnView(
                                title: "STARTING",
                                value: session.startingChips != nil ? "\(Int(session.startingChips!))" : "20,000",
                                valueColor: .white
                            )
                            
                            Divider()
                                .frame(height: 30)
                                .background(Color.white.opacity(0.1))
                            
                            StatColumnView(
                                title: "CURRENT",
                                value: "\(Int(session.currentStack))",
                                valueColor: .white
                            )
                        } else {
                            // Finished tournament: show cash out
                            StatColumnView(
                                title: "CASH OUT",
                                value: "$\(Int(session.currentStack))",
                                valueColor: .white
                            )
                        }
                        
                        Divider()
                            .frame(height: 30)
                            .background(Color.white.opacity(0.1))
                        
                        // Duration
                        StatColumnView(
                            title: "DURATION",
                            value: session.formattedDuration,
                            valueColor: .white
                        )
                    } else {
                        // Cash game stats (existing behavior)
                        // Buy-in
                        StatColumnView(
                            title: "BUY-IN",
                            value: "$\(Int(session.buyIn))",
                            valueColor: .white
                        )
                        
                        Divider()
                            .frame(height: 30)
                            .background(Color.white.opacity(0.1))
                        
                        // Current Stack
                        StatColumnView(
                            title: "CURRENT",
                            value: "$\(Int(session.currentStack))",
                            valueColor: .white
                        )
                        
                        Divider()
                            .frame(height: 30)
                            .background(Color.white.opacity(0.1))
                        
                        // Profit/Loss
                        StatColumnView(
                            title: "PROFIT/LOSS",
                            value: session.formattedProfit,
                            valueColor: Color(session.profitColor)
                        )
                        
                        Divider()
                            .frame(height: 30)
                            .background(Color.white.opacity(0.1))
                        
                        // Duration
                        StatColumnView(
                            title: "DURATION",
                            value: session.formattedDuration,
                            valueColor: .white
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                
                // View button
                Button(action: { showingWatchView = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: session.isLive ? "eye.fill" : "doc.text.fill")
                            .font(.system(size: 14, weight: .medium))
                        
                        Text(session.isLive ? "Watch Live" : "View Recap")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(UIColor(red: 64/255, green: 156/255, blue: 255/255, alpha: 1.0)), // #409CFF
                                Color(UIColor(red: 100/255, green: 180/255, blue: 255/255, alpha: 1.0)) // #64B4FF
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.3))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(session.isLive ? Color.red.opacity(0.3) : Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .background(Color.clear)
        .sheet(isPresented: $showingWatchView) {
            PublicLiveSessionWatchView(
                sessionId: session.id,
                currentUserId: currentUserId
            )
            .environmentObject(userService)
        }
    }
}

// Helper view for stat columns
private struct StatColumnView: View {
    let title: String
    let value: String
    let valueColor: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.gray.opacity(0.8))
                .textCase(.uppercase)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    let sampleSession = PublicLiveSession(
        id: "sample",
        document: [
            "userId": "user123",
            "userName": "John Doe",
            "userProfileImageURL": "",
            "sessionType": "cashGame",
            "gameName": "Aria Poker Room",
            "stakes": "$2/$5",
            "casino": "",
            "buyIn": 500.0,
            "startTime": Timestamp(date: Date().addingTimeInterval(-3600)),
            "isActive": true,
            "currentStack": 750.0,
            "profit": 250.0,
            "duration": 3600.0,
            "lastUpdated": Timestamp(date: Date()),
            "createdAt": Timestamp(date: Date().addingTimeInterval(-3600))
        ]
    )
    
    PublicLiveSessionCard(
        session: sampleSession,
        currentUserId: "currentUser",
        onViewTapped: { print("View tapped") }
    )
    .environmentObject(UserService())
    .background(AppBackgroundView())
} 