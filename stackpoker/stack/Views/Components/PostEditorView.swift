import SwiftUI
import FirebaseFirestore
import PhotosUI
import UIKit

/// A versatile post editor view that can be used for both regular posts and hand posts.
/// This component is shared between the FeedView (for creating text/image posts) and 
/// HandReplayView (for sharing poker hands).
struct PostEditorView: View {
    // Environment objects and state
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService
    
    // Required properties
    let userId: String
    
    // Optional hand data (only for hand posts)
    var hand: ParsedHandHistory?
    
    // View state
    @State private var postText = ""
    @State private var isLoading = false
    @State private var selectedImages: [UIImage] = []
    @State private var imageSelection: [PhotosPickerItem] = []
    @FocusState private var isTextEditorFocused: Bool
    
    // Determines if this is a hand post
    private var isHandPost: Bool {
        hand != nil
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header with user profile
                    HStack(spacing: 12) {
                        if let profileImage = userService.currentUserProfile?.avatarURL {
                            AsyncImage(url: URL(string: profileImage)) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .foregroundColor(.gray)
                                    )
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                                .frame(width: 48, height: 48)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .foregroundColor(.gray)
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let displayName = userService.currentUserProfile?.displayName,
                               !displayName.isEmpty {
                                Text(displayName)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            } else if let username = userService.currentUserProfile?.username {
                                Text(username)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Text(isHandPost ? "Share your hand" : "Create a post")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    
                    // Hand Summary (only for hand posts)
                    if isHandPost, let handData = hand {
                        HandSummaryView(hand: handData)
                            .padding(.horizontal)
                    }
                    
                    // Text Editor
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $postText)
                            .focused($isTextEditorFocused)
                            .foregroundColor(.white)
                            .font(.system(size: 16))
                            .scrollContentBackground(.hidden)
                            .padding()
                            .background(Color.clear)
                        
                        if postText.isEmpty && !isTextEditorFocused {
                            Text(isHandPost ? "Add a comment about your hand..." : "What's on your mind?")
                                .foregroundColor(Color.gray)
                                .font(.system(size: 16))
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    // Image picker and preview (only for regular posts)
                    if !isHandPost {
                        VStack(spacing: 12) {
                            // Image picker button
                            PhotosPicker(selection: $imageSelection, maxSelectionCount: 4, matching: .images) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 16))
                                    Text("Add Photos")
                                        .font(.system(size: 15, weight: .medium))
                                }
                                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 1.0)))
                                )
                            }
                            
                            // Selected images preview
                            if !selectedImages.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
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
                                                        .font(.system(size: 18))
                                                        .foregroundColor(.white)
                                                        .background(
                                                            Circle()
                                                                .fill(Color.black.opacity(0.6))
                                                                .frame(width: 20, height: 20)
                                                        )
                                                }
                                                .padding(6)
                                            }
                                        }
                                    }
                                    .padding(.top, 4)
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    
                    // Character count
                    HStack {
                        Spacer()
                        Text("\(280 - postText.count)")
                            .foregroundColor(postText.count > 280 ? .red : .gray)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(isHandPost ? "Share Hand" : "Create Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: isHandPost ? shareHand : createPost) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(isHandPost ? "Share" : "Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || postText.count > 280)
                    .foregroundColor(postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || postText.count > 280 ? .gray : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
            }
            .onChange(of: imageSelection) { _, newValue in
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
            .onAppear {
                isTextEditorFocused = true
            }
        }
    }
    
    // Create a regular text/image post
    private func createPost() {
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let username = userService.currentUserProfile?.username else { return }
        
        let displayName = userService.currentUserProfile?.displayName
        let profileImage = userService.currentUserProfile?.avatarURL
        
        isLoading = true
        
        Task {
            do {
                try await postService.createPost(
                    content: postText,
                    userId: userId,
                    username: username,
                    displayName: displayName,
                    profileImage: profileImage,
                    images: selectedImages.isEmpty ? nil : selectedImages
                )
                try await postService.fetchPosts()
                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } catch {
                print("Error creating post: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
    
    // Share a hand post
    private func shareHand() {
        guard !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let hand = hand,
              let username = userService.currentUserProfile?.username,
              let profileImage = userService.currentUserProfile?.avatarURL else { return }
        
        let displayName = userService.currentUserProfile?.displayName
        
        isLoading = true
        
        Task {
            do {
                try await postService.createHandPost(
                    content: postText,
                    userId: userId,
                    username: username,
                    displayName: displayName,
                    profileImage: profileImage,
                    hand: hand
                )
                try await postService.fetchPosts()
                DispatchQueue.main.async {
                    isLoading = false
                    dismiss()
                }
            } catch {
                print("Error sharing hand: \(error)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
} 