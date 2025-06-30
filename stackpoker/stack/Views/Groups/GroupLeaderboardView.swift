import SwiftUI
import Kingfisher

// Main view for the group leaderboard
struct GroupLeaderboardView: View {
    @Environment(\.presentationMode) var presentationMode
    let leaderboard: [LeaderboardEntry]
    let groupName: String
    
    // Animation states
    @State private var headerOpacity = 0.0
    @State private var listOpacity = 0.0
    
    var body: some View {
        ZStack {
            // Background
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Custom Navigation Header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        ZStack {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .frame(width: 40, height: 40)
                            
                        Image(systemName: "chevron.left")
                                .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                            .foregroundColor(.white)
                        }
                    }
                    
                    Spacer()
                    
                    VStack {
                        Text("Leaderboard")
                            .font(.custom("PlusJakartaSans-Bold", size: 20))
                            .foregroundColor(.white)
                        Text(groupName)
                            .font(.custom("PlusJakartaSans-Medium", size: 14))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Placeholder for balance
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 40, height: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .opacity(headerOpacity)
                
                // Leaderboard content
                ScrollView {
                    if leaderboard.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, entry in
                                LeaderboardRow(rank: index + 1, entry: entry)
                                    .opacity(listOpacity)
                                    .animation(
                                        .easeOut(duration: 0.5).delay(Double(index) * 0.08),
                                        value: listOpacity
                                    )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                headerOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                listOpacity = 1.0
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 100)
            
            Image(systemName: "hourglass.bottomhalf.fill")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.7))
            
            Text("No Hours Logged")
                .font(.custom("PlusJakartaSans-Bold", size: 22))
                .foregroundColor(.white)
            
            Text("Group members need to track sessions to appear on the leaderboard.")
                .font(.custom("PlusJakartaSans-Medium", size: 16))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
    }
}

// A single row in the leaderboard
struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Rank with special styling for top 3
            HStack(spacing: 4) {
                Text("\(rank)")
                    .font(.custom("PlusJakartaSans-Bold", size: 18))
                    .foregroundColor(.white)
                
                if let icon = rankIcon() {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(rankColor())
                }
            }
            .frame(width: 40)
            
            // User Avatar
            KFImage(entry.user.avatarURL.flatMap(URL.init))
                .placeholder {
                    Image(systemName: "person.fill")
                        .font(.custom("PlusJakartaSans-Medium", size: 20))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 48, height: 48)
                        .background(Color.black.opacity(0.2))
                        .clipShape(Circle())
                }
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            
            // User Info
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.user.displayName ?? "Unknown User")
                    .font(.custom("PlusJakartaSans-SemiBold", size: 16))
                    .foregroundColor(.white)
                Text("@\(entry.user.username)")
                    .font(.custom("PlusJakartaSans-Medium", size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Hours Played
            Text(String(format: "%.1f hrs", entry.totalHours))
                .font(.custom("PlusJakartaSans-Bold", size: 18))
                .foregroundColor(rankColor())
        }
        .padding(16)
        .background(
            ZStack {
                Color.black.opacity(0.2)
                
                // Add a glow for top 3
                if rank <= 3 {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(rankColor().opacity(0.5), lineWidth: 2)
                        .blur(radius: 3)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func rankIcon() -> String? {
        switch rank {
        case 1: return "crown.fill"
        case 2: return "star.fill"
        case 3: return "star.fill"
        default: return nil
        }
    }
    
    private func rankColor() -> Color {
        switch rank {
        case 1: return Color(red: 255/255, green: 193/255, blue: 64/255) // Gold
        case 2: return Color(red: 192/255, green: 192/255, blue: 192/255) // Silver
        case 3: return Color(red: 205/255, green: 127/255, blue: 50/255)  // Bronze
        default: return .white
        }
    }
}

// Model for a leaderboard entry
struct LeaderboardEntry: Identifiable, Hashable {
    let id: String // userId
    let user: UserProfile
    let totalHours: Double
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LeaderboardEntry, rhs: LeaderboardEntry) -> Bool {
        lhs.id == rhs.id
    }
} 