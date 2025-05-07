import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore

struct FeedView: View {
    @StateObject private var postService = PostService()
    @EnvironmentObject var userService: UserService
    @State private var showingNewPost = false
    @State private var isRefreshing = false
    @State private var showingDiscoverUsers = false
    let userId: String
    
    var body: some View {
        ZStack {
            Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                .ignoresSafeArea()
            VStack {
                Spacer()
                Text("Coming Soon")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                    .font(.system(size: 17, weight: .medium))
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: createPost) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Post")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || postText.count > 280)
                    .foregroundColor(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || postText.count > 280 ? .gray : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || postText.count > 280 
                            ? Color.clear 
                            : Color(UIColor(red: 20/255, green: 50/255, blue: 30/255, alpha: 0.3))
                    )
                    .cornerRadius(16)
                }
            }
        }
        .onAppear {
            isTextEditorFocused = true
        }
    }
    
    private func createPost() {
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        
        Task {
            do {
                try await postService.createPost(
                    content: postText,
                    userId: userId,
                    username: userProfile.username,
                    displayName: userProfile.displayName,
                    profileImage: userProfile.avatarURL,
                    images: selectedImages.isEmpty ? nil : selectedImages
                )
                try await postService.fetchPosts()
                DispatchQueue.main.async {
                    dismiss()
                }
            } catch {
                print("Error creating post: \(error)")
            }
            isLoading = false
        }
    }
}

// Helper for time ago display
extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
} 
