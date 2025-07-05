import SwiftUI
import Kingfisher
import FirebaseAuth
import UIKit

struct RecommendedUsersPopup: View {
    let onContinue: () -> Void
    let onDismiss: () -> Void
    @EnvironmentObject var userService: UserService
    
    @State private var recommendedUsers: [UserProfile] = []
    @State private var isLoading: Bool = true
    @State private var followedUsers: Set<String> = []
    @State private var isProcessingFollow: Set<String> = []
    
    // Default users to auto-follow (Wolfgang and Slick)
    private let defaultFollowUserIds = [
        "VZryEFVeM2eUpwjWHyNkqh7c3L22", // Wolfgang
        "5bC6BlYB27g0dfpmaXI8r3bO8iF2"  // Slick
    ]
    
    // Additional recommended users to show but not auto-follow
    private let additionalRecommendedUserIds = [
        "qY3HAlHvBzWDCPMRMRO4lW6KCRN2" // News bot
    ]
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    // Don't dismiss on background tap to ensure users see recommendations
                }
            
            // Main popup with glass effect
            VStack(spacing: 20) {
                // Header with animated icon
                VStack(spacing: 16) {
                    // Animated icon
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.2),
                                                Color.purple.opacity(0.1)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.5), .white.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                        
                        Image(systemName: "person.2.circle.fill")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(.white)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .scaleEffect(isLoading ? 0.9 : 1.0)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isLoading)
                    
                    VStack(spacing: 6) {
                        Text("Discover Players")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Follow interesting players to build your network")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                
                // Users list
                if isLoading {
                    VStack(spacing: 12) {
                        ForEach(0..<6) { _ in
                            RecommendedUserSkeletonView()
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        // Show at least 6 users total
                        ForEach(recommendedUsers.prefix(6), id: \.id) { user in
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
                
                // Continue button with enhanced styling
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onContinue()
                }) {
                    HStack {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white, Color.white.opacity(0.95)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                            .shadow(color: .white.opacity(0.5), radius: 10, y: 3)
                    )
                }
                .buttonStyle(ScaleButtonStyle())
            }
            .padding(24)
            .background(
                ZStack {
                    // Base blur
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                    
                    // Gradient overlay
                    RoundedRectangle(cornerRadius: 24)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.3),
                                    Color.black.opacity(0.2)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Border
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.white.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(0.3), radius: 30, y: 15)
            .shadow(color: .purple.opacity(0.1), radius: 40, y: 20)
            .frame(maxWidth: 380)
            .padding(.horizontal, 32)
            .scaleEffect(isLoading ? 0.95 : 1.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isLoading)
        }
        .onAppear {
            Task {
                await loadRecommendedUsers()
            }
        }
    }
    
    private func loadRecommendedUsers() async {
        // First, automatically follow only the default users (Wolfgang and Slick)
        await autoFollowRecommendedUsers()
        
        // Load user profiles for display
        var users: [UserProfile] = []
        
        // Fetch default follow users first (Wolfgang and Slick)
        for userId in defaultFollowUserIds {
            await userService.fetchUser(id: userId)
            if let user = userService.loadedUsers[userId] {
                users.append(user)
                followedUsers.insert(userId) // Mark as followed since we auto-followed them
            }
        }
        
        // Fetch additional recommended users (news bot)
        for userId in additionalRecommendedUserIds {
            await userService.fetchUser(id: userId)
            if let user = userService.loadedUsers[userId] {
                users.append(user)
                // Don't mark as followed - user can choose to follow
            }
        }
        
        // Then fetch top users to ensure we have at least 6 total
        do {
            let allRecommendedIds = defaultFollowUserIds + additionalRecommendedUserIds
            let topUsers = try await userService.fetchSuggestedUsers(limit: 15) // Fetch more to ensure we have enough
            let filteredTopUsers = topUsers.filter { user in
                !allRecommendedIds.contains(user.id) && // Exclude all recommended users
                user.id != Auth.auth().currentUser?.uid // Exclude current user
            }.prefix(max(3, 6 - users.count)) // Fill up to at least 6 users total
            
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
        
        // Only auto-follow the default users (Wolfgang and Slick)
        for userId in defaultFollowUserIds {
            do {
                // Check if already following to avoid duplicates
                let alreadyFollowing = await userService.isUserFollowing(targetUserId: userId, currentUserId: currentUserId)
                if !alreadyFollowing {
                    try await userService.followUser(userIdToFollow: userId)
                    print("✅ Auto-followed user: \(userId)")
                }
                _ = await MainActor.run {
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
                    _ = await MainActor.run {
                        followedUsers.remove(user.id)
                    }
                } else {
                    try await userService.followUser(userIdToFollow: user.id)
                    _ = await MainActor.run {
                        followedUsers.insert(user.id)
                    }
                }
            } catch {
                print("❌ Error toggling follow for user \(user.id): \(error)")
            }
            
            _ = await MainActor.run {
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
            
            // Follow button with Apple-style animation
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    onFollowToggle()
                }
            }) {
                Group {
                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isFollowed ? .white : .black))
                            .scaleEffect(0.7)
                    } else {
                        HStack(spacing: 3) {
                            if isFollowed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Text(isFollowed ? "Following" : "Follow")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                    }
                }
                .foregroundColor(isFollowed ? .white : .black)
                .frame(width: isFollowed ? 90 : 75, height: 32)
                .background(
                    ZStack {
                        if isFollowed {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                )
                        } else {
                            Capsule()
                                .fill(Color.white)
                                .shadow(color: .white.opacity(0.5), radius: 6, y: 2)
                        }
                    }
                )
            }
            .disabled(isProcessing)
            .buttonStyle(ScaleButtonStyle())
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

