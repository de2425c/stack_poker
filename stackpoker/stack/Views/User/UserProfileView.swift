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
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 80, height: 80)
                                    .foregroundColor(.gray)
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
                    
                    // Placeholder for user's posts
                    Text("User's Posts")
                        .font(.headline)
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
                        PostView(
                            post: post, 
                            onLike: { /* Implement like for profile view if needed */ }, 
                            onComment: { /* Implement comment for profile view if needed */ }, 
                            userId: loggedInUserId ?? "" // Pass logged-in user ID
                        )
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
                // TODO: Fetch user's posts - profilePostService.fetchPosts(forUserId: userId)
                // TODO: Check if current user is following this user - self.isFollowing = await userService.isFollowing(userId)
                print("Displaying UserProfileView for userId: \(userId)")
            }
        }
    }

    func toggleFollow() {
        guard let currentLoggedInUserId = loggedInUserId, userId != currentLoggedInUserId else { return }
        isProcessingFollow = true
        Task {
            // TODO: Implement actual follow/unfollow logic in UserService
            // For example: 
            // if isFollowing {
            //     try? await userService.unfollowUser(userIdToUnfollow: userId, currentUserId: currentLoggedInUserId)
            // } else {
            //     try? await userService.followUser(userIdToFollow: userId, currentUserId: currentLoggedInUserId)
            // }
            // self.isFollowing.toggle() // Toggle based on successful operation
            // await userService.fetchUser(id: userId) // Refresh user data to update follower count
            // await userService.fetchUserProfile() // Refresh current user's following count (if shown elsewhere)
            
            // Placeholder toggle
            self.isFollowing.toggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { // Simulate network request
                 isProcessingFollow = false
                 // After actual operation, refresh the user whose profile is being viewed to update their follower count
                 Task { await userService.fetchUser(id: userId) }
                 // And refresh the current user's profile to update their following count
                 if let LUID = loggedInUserId { Task { await userService.fetchUser(id: LUID) } }
            }
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
