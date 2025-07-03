import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

// MARK: - Activity Content View (Recent Posts)
struct ActivityContentView: View {
    let userId: String 
    @EnvironmentObject private var userService: UserService 
    @EnvironmentObject private var postService: PostService
    @Binding var selectedPostForNavigation: Post? 
    // @Binding var showingPostDetailSheet: Bool // This binding is no longer needed here

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if postService.isLoading && postService.posts.filter({ $0.userId == userId }).isEmpty {
                 ProgressView().padding().frame(maxWidth: .infinity, alignment: .center)
            } else if postService.posts.filter({ $0.userId == userId }).isEmpty {
                Text("No recent posts to display.")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .background(Color.black.opacity(0.15).cornerRadius(12))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(postService.posts.filter { $0.userId == userId }) { post in 
                            PostView(
                                post: post,
                                onLike: { Task { try? await postService.toggleLike(postId: post.id ?? "", userId: userService.currentUserProfile?.id ?? "") } },
                                onComment: { /* If PostView has a comment button that navigates, it might need its own programmatic trigger */ },
                                userId: userService.currentUserProfile?.id ?? ""
                            )
                            .padding(.leading, 8) // Reduced horizontal padding, more to the left
                            .contentShape(Rectangle()) // Ensure the whole area is tappable
                            .onTapGesture {
                                // Direct navigation instead of sheet
                                self.selectedPostForNavigation = post
                            }
                            .background(
                                NavigationLink(
                                    destination: PostDetailView(post: post, userId: userId),
                                    isActive: Binding<Bool>(
                                       get: { selectedPostForNavigation?.id == post.id },
                                       set: { if !$0 { selectedPostForNavigation = nil } }
                                    ),
                                    label: { EmptyView() }
                                ).opacity(0)
                            )
                        }
                    }
                    .padding(.top, 0) // Removed vertical padding, posts will be closer to the top
                }
                .padding(.top, 8) // Reduced top padding for the ScrollView
                .padding(.top, 10) // Reduced from 50 to 10 points to minimize space under header
            }
        }
        .padding(.bottom, 8) // Reduced bottom padding for the entire ActivityContentView
        // .onAppear is handled by ProfileView's .onChange for selectedTab
    }
}
