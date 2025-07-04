import SwiftUI
import Kingfisher
import FirebaseAuth

struct RecommendedUsersPopup: View {
    let onContinue: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject var userService: UserService
    
    @State private var recommendedUsers: [UserProfile] = []
    @State private var isLoading: Bool = true
    @State private var followedUsers: Set<String> = []
    @State private var isProcessingFollow: Set<String> = []
    
    // Hardcoded recommended user IDs
    private let recommendedUserIds = [
        "VZryEFVeM2eUpwjWHyNkqh7c3L22",
        "5bC6BlYB27g0dfpmaXI8r3bO8iF2",
        "qY3HAlHvBzWDCPMRMRO4lW6KCRN2"
    ]
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    // Don't dismiss on background tap to ensure users see recommendations
                }
            
            // Main popup
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(red: 64/255, green: 156/255, blue: 255/255),
                                        Color(red: 100/255, green: 180/255, blue: 255/255)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 6) {
                        Text("Follow Top Players")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Text("Connect with poker players to see their content and sessions")
                            .font(.system(size: 15))
                            .foregroundColor(.gray.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                }
                
                // Users list
                if isLoading {
                    VStack(spacing: 12) {
                        ForEach(0..<8) { _ in
                            RecommendedUserSkeletonView()
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        // First show the 3 hardcoded users
                        ForEach(recommendedUsers.prefix(3), id: \.id) { user in
                            RecommendedUserRow(
                                user: user,
                                isFollowed: followedUsers.contains(user.id),
                                isProcessing: isProcessingFollow.contains(user.id),
                                onFollowToggle: {
                                    toggleFollow(user: user)
                                }
                            )
                        }
                        
                        // Divider
                        if recommendedUsers.count > 3 {
                            Divider()
                                .background(Color.white.opacity(0.2))
                                .padding(.vertical, 8)
                        }
                        
                        // Then show the top 5 most followed users
                        ForEach(recommendedUsers.dropFirst(3).prefix(5), id: \.id) { user in
                            RecommendedUserRow(
                                user: user,
                                isFollowed: followedUsers.contains(user.id),
                                isProcessing: isProcessingFollow.contains(user.id),
                                onFollowToggle: {
                                    toggleFollow(user: user)
                                }
                            )
                        }
                    }
                }
                
                // Continue button
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255),
                                    Color(red: 100/255, green: 180/255, blue: 255/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(UIColor(red: 20/255, green: 20/255, blue: 24/255, alpha: 1.0)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            )
            .frame(maxWidth: 360)
            .padding(.horizontal, 32)
        }
        .onAppear {
            Task {
                await loadRecommendedUsers()
            }
        }
    }
    
    private func loadRecommendedUsers() async {
        // First, automatically follow the 3 hardcoded users
        await autoFollowRecommendedUsers()
        
        // Load user profiles for the hardcoded users
        var users: [UserProfile] = []
        
        // Fetch hardcoded users first
        for userId in recommendedUserIds {
            await userService.fetchUser(id: userId)
            if let user = userService.loadedUsers[userId] {
                users.append(user)
                followedUsers.insert(userId) // Mark as followed since we auto-followed them
            }
        }
        
        // Then fetch top 5 most followed users (excluding the hardcoded ones and current user)
        do {
            let topUsers = try await userService.fetchSuggestedUsers(limit: 10)
            let filteredTopUsers = topUsers.filter { user in
                !recommendedUserIds.contains(user.id) // Exclude hardcoded users
            }.prefix(5)
            
            users.append(contentsOf: filteredTopUsers)
            
            await MainActor.run {
                self.recommendedUsers = users
                self.isLoading = false
            }
        } catch {
            print("❌ Error loading recommended users: \(error)")
            await MainActor.run {
                self.recommendedUsers = users // Just show hardcoded users if top users fail
                self.isLoading = false
            }
        }
    }
    
    private func autoFollowRecommendedUsers() async {
        // Get current user ID from Auth if profile isn't loaded yet
        guard let currentUserId = userService.currentUserProfile?.id ?? Auth.auth().currentUser?.uid else { 
            print("❌ No current user ID available for auto-following")
            return 
        }
        
        for userId in recommendedUserIds {
            do {
                // Check if already following to avoid duplicates
                let alreadyFollowing = await userService.isUserFollowing(targetUserId: userId, currentUserId: currentUserId)
                if !alreadyFollowing {
                    try await userService.followUser(userIdToFollow: userId)
                    print("✅ Auto-followed user: \(userId)")
                }
                await MainActor.run {
                    followedUsers.insert(userId)
                }
            } catch {
                print("❌ Failed to auto-follow user \(userId): \(error)")
            }
        }
    }
    
    private func toggleFollow(user: UserProfile) {
        guard !isProcessingFollow.contains(user.id) else { return }
        
        isProcessingFollow.insert(user.id)
        
        Task {
            do {
                if followedUsers.contains(user.id) {
                    try await userService.unfollowUser(userIdToUnfollow: user.id)
                    await MainActor.run {
                        followedUsers.remove(user.id)
                    }
                } else {
                    try await userService.followUser(userIdToFollow: user.id)
                    await MainActor.run {
                        followedUsers.insert(user.id)
                    }
                }
            } catch {
                print("❌ Error toggling follow for user \(user.id): \(error)")
            }
            
            await MainActor.run {
                isProcessingFollow.remove(user.id)
            }
        }
    }
}

// MARK: - Supporting Views

struct RecommendedUserRow: View {
    let user: UserProfile
    let isFollowed: Bool
    let isProcessing: Bool
    let onFollowToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let avatarURL = user.avatarURL, let url = URL(string: avatarURL) {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                } else {
                    PlaceholderAvatarView(size: 50)
                }
            }
            
            // User info
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName ?? user.username)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("@\(user.username)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                
                if user.followersCount > 0 {
                    Text("\(user.followersCount) followers")
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Follow button
            Button(action: onFollowToggle) {
                Group {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Text(isFollowed ? "Following" : "Follow")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(isFollowed ? .gray : .white)
                .frame(width: 80, height: 32)
                .background(
                    Group {
                        if isFollowed {
                            Color.gray.opacity(0.3)
                        } else {
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 64/255, green: 156/255, blue: 255/255),
                                    Color(red: 100/255, green: 180/255, blue: 255/255)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                )
                .cornerRadius(16)
            }
            .disabled(isProcessing)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 4)
    }
}

struct RecommendedUserSkeletonView: View {
    @State private var shimmerOffset: CGFloat = -200
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar skeleton
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.3), Color.clear]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmerOffset)
                        .clipped()
                )
            
            VStack(alignment: .leading, spacing: 4) {
                // Name skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 120, height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.3), Color.clear]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerOffset)
                            .clipped()
                    )
                
                // Username skeleton
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 80, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.3), Color.clear]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: shimmerOffset)
                            .clipped()
                    )
            }
            
            Spacer()
            
            // Button skeleton
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 80, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.clear, Color.white.opacity(0.3), Color.clear]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmerOffset)
                        .clipped()
                )
        }
        .onAppear {
            withAnimation(Animation.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 200
            }
        }
    }
}

// MARK: - Preview
#Preview {
    RecommendedUsersPopup(
        onContinue: { print("Continue tapped") },
        onDismiss: { print("Dismiss tapped") }
    )
    .environmentObject(UserService())
} 