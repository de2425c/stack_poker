import SwiftUI
import FirebaseAuth
import Kingfisher // For displaying avatar image

struct UserProfileView: View {
    let userId: String // The ID of the profile being viewed
    @StateObject private var profilePostService = PostService() // For fetching user's posts
    @EnvironmentObject var userService: UserService // To get user details and current user info

    // State for the follow button
    @State private var isFollowing: Bool = false // Placeholder: actual value needs to be fetched
    @State private var isProcessingFollow: Bool = false

    private var loggedInUserId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private var isCurrentUserProfile: Bool {
        userId == loggedInUserId
    }

    var body: some View {
        ScrollView {
            if let user = userService.loadedUsers[userId] {
                VStack(alignment: .leading, spacing: 16) {
                    // Profile Header
                    HStack(spacing: 16) {
                        // Avatar Image
                        Group {
                            if let avatarURLString = user.avatarURL, let url = URL(string: avatarURLString) {
                                KFImage(url)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 1))
                            } else {
                                PlaceholderAvatarView(size: 80)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName ?? user.username)
                                .font(.title2).bold()
                                .foregroundColor(.white)
                            Text("@\(user.username)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                        Spacer() // Pushes content to left, button to right if in HStack
                    }
                    .padding(.horizontal)

                    // Follow/Edit Profile Button & Stats
                    HStack(spacing: 20) {
                        StatView(count: user.followersCount, label: "Followers")
                        StatView(count: user.followingCount, label: "Following")
                        Spacer()
                        if !isCurrentUserProfile {
                            Button(action: toggleFollow) {
                                Text(isFollowing ? "Unfollow" : "Follow")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isFollowing ? .white : .black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(isFollowing ? Color.gray.opacity(0.7) : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .cornerRadius(20)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20)
                                            .stroke(isFollowing ? Color.gray : Color.clear, lineWidth: 1)
                                    )
                            }
                            .disabled(isProcessingFollow)
                            
                            // Block Button
                            Button(action: { 
                                // Action for block button (not implemented)
                                print("Block button tapped for user: \(user.username)")
                            }) {
                                Image(systemName: "person.crop.circle.badge.xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.red.opacity(0.7))
                                    .cornerRadius(20)
                            }
                        } else {
                            // Placeholder for "Edit Profile" button for current user
                            Button(action: { /* TODO: Implement Edit Profile Navigation */ }) {
                                Text("Edit Profile")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.5))
                                    .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Bio
                    if let bio = user.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.body)
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal)
                            .lineLimit(nil) // Allow multi-line bio
                    }
                    
                    Divider().padding(.horizontal)
                    
                    // Changed from "User's Posts"
                    Text("Recent Activity")
                        .font(.plusJakarta(.title2, weight: .bold)) // Using Plus Jakarta Sans, bold, size 22-24 equivalent
                        .foregroundColor(.white) // Ensure text is white
                        .padding([.horizontal, .top])
                    
                    if profilePostService.posts.isEmpty && !profilePostService.isLoading {
                        Text("This user hasn't made any posts yet.")
                            .foregroundColor(.gray)
                            .padding()
                    } else if profilePostService.isLoading {
                        ProgressView().padding()
                    }
                    
                    // List of user's posts (using existing PostView)
                    ForEach(profilePostService.posts) { post in
                        NavigationLink(destination: PostDetailView(post: post, userId: loggedInUserId ?? "").environmentObject(userService).environmentObject(profilePostService)) {
                            PostView(
                                post: post, 
                                onLike: { 
                                    Task { try? await profilePostService.toggleLike(postId: post.id ?? "", userId: loggedInUserId ?? "") } 
                                }, 
                                onComment: { /* Comment handling for profile view if needed */ }, 
                                userId: loggedInUserId ?? "" // Pass logged-in user ID
                            )
                        }
                        .buttonStyle(PlainButtonStyle()) // Ensures the whole PostView is tappable like a button
                        Divider()
                    }
                    
                }
                .padding(.vertical)
            } else {
                // Loading state or user not found
                VStack {
                    ProgressView()
                    Text("Loading profile...")
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(AppBackgroundView().ignoresSafeArea()) // Assuming AppBackgroundView exists
        .onAppear {
            Task {
                if userService.loadedUsers[userId] == nil {
                    await userService.fetchUser(id: userId) // Fetch user details if not already loaded
                }
                // Fetch initial follow state
                if let currentLoggedInUserId = loggedInUserId {
                    self.isFollowing = await userService.isUserFollowing(targetUserId: userId, currentUserId: currentLoggedInUserId)
                }
                // Fetch user's posts
                try? await profilePostService.fetchPosts(forUserId: userId)

            }
        }
    }

    func toggleFollow() {
        guard let currentLoggedInUserId = loggedInUserId, userId != currentLoggedInUserId else { return }
        
        isProcessingFollow = true
        let actionIsFollow = !isFollowing // The action we are about to perform

        Task {
            do {
                if actionIsFollow {
                    try await userService.followUser(userIdToFollow: userId)
                } else {
                    try await userService.unfollowUser(userIdToUnfollow: userId)
                }

                
                // Refresh both user profiles to get updated counts
                await userService.fetchUser(id: userId) 
                await userService.fetchUser(id: currentLoggedInUserId) 
                if userService.currentUserProfile?.id == currentLoggedInUserId {
                     try? await userService.fetchUserProfile() 
                }

                // Re-fetch the follow status from the source of truth
                self.isFollowing = await userService.isUserFollowing(targetUserId: userId, currentUserId: currentLoggedInUserId)

            } catch {

                // Optionally, revert optimistic UI update if server operation failed
                // self.isFollowing = !actionIsFollow 
            }
            isProcessingFollow = false
        }
    }
}

// Helper view for stats
struct StatView: View {
    let count: Int
    let label: String

    var body: some View {
        VStack {
            Text("\(count)")
                .font(.headline).bold()
                .foregroundColor(.white)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
}

// Preview needs adjustment for the new structure
struct UserProfileView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleUserId = "sampleUser123"
        let mockUserService = UserService()
        // Preload a sample user for preview
        mockUserService.loadedUsers[sampleUserId] = UserProfile(
            id: sampleUserId, 
            username: "sampleUser", 
            displayName: "Sample User Display Name", 
            createdAt: Date(), 
            favoriteGames: ["Poker", "Chess"],
            bio: "This is a sample bio for preview purposes. It can be a bit longer to see how it wraps.", 
            avatarURL: nil, // Or a placeholder image URL string
            location: "Sample Location", 
            favoriteGame: "Poker", 
            followersCount: 125, 
            followingCount: 78
        )
        
        return NavigationView {
            UserProfileView(userId: sampleUserId)
                .environmentObject(mockUserService)
                //.environmentObject(PostService()) // If PostService is needed for previewing posts
        }
        .preferredColorScheme(.dark)
    }
} 
