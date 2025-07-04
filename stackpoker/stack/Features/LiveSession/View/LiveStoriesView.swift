import SwiftUI
import Kingfisher
import FirebaseFirestore

struct LiveStoriesView: View {
    let liveSessions: [PublicLiveSession]
    let currentUserId: String
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        if !liveSessions.isEmpty {
            VStack(spacing: 0) {
                // Stories container
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(liveSessions) { session in
                            LiveStoryCircle(
                                session: session,
                                currentUserId: currentUserId
                            )
                            .environmentObject(userService)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                
                // Divider
                Divider()
                    .frame(height: 0.5)
                    .background(Color.white.opacity(0.1))
            }
        }
    }
}

struct LiveStoryCircle: View {
    let session: PublicLiveSession
    let currentUserId: String
    @EnvironmentObject var userService: UserService
    @State private var showingWatchView = false
    
    private var isOwnSession: Bool {
        return session.userId == currentUserId
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Profile circle with live indicator
            ZStack {
                // Main profile circle
                Button(action: { showingWatchView = true }) {
                    Group {
                        if !session.userProfileImageURL.isEmpty, let url = URL(string: session.userProfileImageURL) {
                            KFImage(url)
                                .placeholder {
                                    PlaceholderAvatarView(size: 64)
                                }
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        } else {
                            PlaceholderAvatarView(size: 64)
                        }
                    }
                    .overlay(
                        // Live gradient border
                        Circle()
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.red,
                                        Color.red.opacity(0.8),
                                        Color.orange,
                                        Color.red
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .scaleEffect(1.1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Live indicator in bottom right
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            Circle()
                                .fill(Color.black)
                                .frame(width: 20, height: 20)
                            
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                                .scaleEffect(session.isLive ? 1.0 : 0.8)
                                .animation(
                                    session.isLive ? 
                                    Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true) : 
                                    .default,
                                    value: session.isLive
                                )
                        }
                        .offset(x: 8, y: 8)
                    }
                }
            }
            .frame(width: 72, height: 72)
            
            // Username
            Text(session.userName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 72)
                .multilineTextAlignment(.center)
        }
        .sheet(isPresented: $showingWatchView) {
            PublicLiveSessionWatchView(
                sessionId: session.id,
                currentUserId: currentUserId
            )
            .environmentObject(userService)
        }
    }
}



#Preview {
    let sampleSessions = [
        PublicLiveSession(
            id: "1",
            document: [
                "userId": "user1",
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
        ),
        PublicLiveSession(
            id: "2",
            document: [
                "userId": "user2",
                "userName": "Jane Smith",
                "userProfileImageURL": "",
                "sessionType": "tournament",
                "gameName": "WSOP Event #1",
                "stakes": "",
                "casino": "Rio",
                "buyIn": 1000.0,
                "startTime": Timestamp(date: Date().addingTimeInterval(-7200)),
                "isActive": true,
                "currentStack": 15000.0,
                "profit": 0.0,
                "duration": 7200.0,
                "lastUpdated": Timestamp(date: Date()),
                "createdAt": Timestamp(date: Date().addingTimeInterval(-7200))
            ]
        )
    ]
    
    LiveStoriesView(
        liveSessions: sampleSessions,
        currentUserId: "currentUser"
    )
    .environmentObject(UserService())
    .background(AppBackgroundView())
} 