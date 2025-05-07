import SwiftUI
import PhotosUI
import FirebaseStorage
import FirebaseFirestore
import FirebaseAuth

struct FeedView: View {
    @StateObject private var postService = PostService()
    @EnvironmentObject var userService: UserService
    @State private var showingNewPost = false
    @State private var isRefreshing = false
    @State private var showingDiscoverUsers = false
    @State private var isLoading = false
    @State private var postText = ""
    @State private var selectedImages: [UIImage] = []
    @Environment(\.dismiss) private var dismiss
    
    let userId: String
    
    init(userId: String = Auth.auth().currentUser?.uid ?? "") {
        self.userId = userId
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                VStack {
                    if postService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else if postService.posts.isEmpty {
                        VStack(spacing: 16) {
                            Text("No posts yet")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("Follow other players or create a post to see content here")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            
                            Button(action: {
                                showingDiscoverUsers = true
                            }) {
                                Text("Discover Players")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .cornerRadius(12)
                            }
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 20)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(postService.posts) { post in
                                    PostCell(post: post)
                                        .padding(.horizontal, 16)
                                }
                                
                                if !postService.isLoading {
                                    Color.clear
                                        .frame(height: 50)
                                        .onAppear {
                                            Task {
                                                try? await postService.fetchMorePosts()
                                            }
                                        }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .refreshable {
                            isRefreshing = true
                            Task {
                                try? await postService.fetchPosts()
                                isRefreshing = false
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Feed")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingNewPost = true
                    }) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(.white)
                            .font(.system(size: 20))
                    }
                }
            }
            .sheet(isPresented: $showingNewPost) {
                CreatePostView(userId: userId)
            }
            .sheet(isPresented: $showingDiscoverUsers) {
                DiscoverUsersView(userId: userId)
            }
            .onAppear {
                Task {
                    try? await postService.fetchPosts()
                }
            }
        }
    }
}

struct CreatePostView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userService: UserService
    @StateObject private var postService = PostService()
    @State private var postText = ""
    @State private var isLoading = false
    @State private var selectedImages: [UIImage] = []
    @State private var imageSelection: [PhotosPickerItem] = []
    let userId: String
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $postText)
                            .foregroundColor(.white)
                            .frame(minHeight: 150)
                            .padding(10)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)
                            .onAppear {
                                UITextView.appearance().backgroundColor = .clear
                            }
                        
                        if postText.isEmpty {
                            Text("What's on your mind?")
                                .foregroundColor(.gray)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                        }
                    }
                    
                    // Image picker and preview
                    VStack {
                        PhotosPicker(selection: $imageSelection, maxSelectionCount: 4, matching: .images) {
                            HStack {
                                Image(systemName: "photo")
                                Text("Add Photos")
                            }
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(8)
                        }
                        
                        if !selectedImages.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(0..<selectedImages.count, id: \.self) { index in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: selectedImages[index])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            
                                            Button(action: {
                                                selectedImages.remove(at: index)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .background(Color.black.opacity(0.7))
                                                    .clipShape(Circle())
                                            }
                                            .padding(5)
                                        }
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding()
                .onChange(of: imageSelection) { oldValue, newValue in
                    Task {
                        selectedImages.removeAll()
                        for item in newValue {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let image = UIImage(data: data) {
                                selectedImages.append(image)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Create Post")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
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
                }
            }
        }
    }
    
    private func createPost() {
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        
        Task {
            do {
                // Get user profile info
                let userProfile = userService.currentUserProfile
                
                try await postService.createPost(
                    content: postText,
                    userId: userId,
                    username: userProfile?.username ?? "",
                    displayName: userProfile?.displayName,
                    profileImage: userProfile?.avatarURL,
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

struct PostCell: View {
    let post: Post
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User info
            HStack {
                if let profileImageURL = post.profileImage, !profileImageURL.isEmpty {
                    AsyncImage(url: URL(string: profileImageURL)) { image in
                        image
                            .resizable()
                            .scaledToFill()
                    } placeholder: {
                        Color.gray
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.displayName ?? "@\(post.username)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("@\(post.username)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text(post.createdAt.timeAgoDisplay())
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
            }
            
            // Post content
            Text(post.content)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
            
            // Images if any
            if let imageURLs = post.imageURLs, !imageURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageURLs, id: \.self) { url in
                            AsyncImage(url: URL(string: url)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Color.gray
                            }
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            
            // Action buttons
            HStack(spacing: 24) {
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: post.isLiked ? "heart.fill" : "heart")
                            .foregroundColor(post.isLiked ? .red : .gray)
                        
                        if post.likes > 0 {
                            Text("\(post.likes)")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Button(action: {}) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .foregroundColor(.gray)
                        
                        if post.comments > 0 {
                            Text("\(post.comments)")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(Color(UIColor.systemGray6).opacity(0.2))
        .cornerRadius(12)
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
