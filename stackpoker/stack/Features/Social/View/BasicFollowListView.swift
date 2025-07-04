 import SwiftUI
import FirebaseFirestore
import Kingfisher

struct BasicFollowListView: View {
    let userId: String
    let listType: FollowListType
    let userName: String
    
    @StateObject private var viewModel = BasicFollowListViewModel()
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userService: UserService
    
    private var loggedInUserId: String? {
        userService.currentUserProfile?.id
    }
    
    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()
            
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                    Spacer()
                } else if viewModel.users.isEmpty {
                    Spacer()
                    Text(listType == .followers ? "No followers yet" : "Not following anyone")
                        .foregroundColor(.gray)
                        .font(.body)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.users) { user in
                                BasicUserRow(
                                    user: user,
                                    loggedInUserId: loggedInUserId
                                )
                                .environmentObject(userService)
                                .padding(.horizontal)
                            }
                        }
                        .padding(.top, 16)
                    }
                }
            }
        }
        .navigationTitle(listType == .followers ? "\(userName)'s Followers" : "\(userName) Following")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadUsers(userId: userId, listType: listType)
        }
    }
}

struct BasicUserRow: View {
    let user: UserProfile
    let loggedInUserId: String?
    
    @State private var isFollowing = false
    @State private var isProcessingFollow = false
    @EnvironmentObject var userService: UserService
    
    private var shouldShowFollowButton: Bool {
        guard let actualLoggedInUserId = loggedInUserId else { return false }
        return user.id != actualLoggedInUserId
    }
    
    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(destination: UserProfileView(userId: user.id).environmentObject(userService)) {
                HStack(spacing: 12) {
                    // Profile Image
                    Group {
                        if let avatarURLString = user.avatarURL, let url = URL(string: avatarURLString) {
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
                    
                    // User Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.displayName ?? user.username)
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .semibold))
                            .lineLimit(1)
                        
                        Text("@\(user.username)")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                            .lineLimit(1)
                        
                        if let bio = user.bio, !bio.isEmpty {
                            Text(bio)
                                .foregroundColor(.gray)
                                .font(.system(size: 13))
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Follow Button
            if shouldShowFollowButton {
                Button(action: toggleFollow) {
                    if isProcessingFollow {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isFollowing ? .white : .black))
                            .frame(width: 16, height: 16)
                    } else {
                        Text(isFollowing ? "Following" : "Follow")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isFollowing ? .white : .black)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isFollowing ? Color.gray.opacity(0.3) : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                )
                .disabled(isProcessingFollow)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color.black.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            checkFollowStatus()
        }
    }
    
    private func checkFollowStatus() {
        guard let actualLoggedInUserId = loggedInUserId, user.id != actualLoggedInUserId else {
            return
        }
        
        Task {
            let following = await userService.isUserFollowing(targetUserId: user.id, currentUserId: actualLoggedInUserId)
            await MainActor.run {
                self.isFollowing = following
            }
        }
    }
    
    private func toggleFollow() {
        guard !isProcessingFollow, let actualLoggedInUserId = loggedInUserId else { return }
        
        isProcessingFollow = true
        
        Task {
            do {
                if isFollowing {
                    try await userService.unfollowUser(userIdToUnfollow: user.id)
                } else {
                    try await userService.followUser(userIdToFollow: user.id)
                }
                
                await MainActor.run {
                    self.isFollowing.toggle()
                    self.isProcessingFollow = false
                }
            } catch {
                print("Error toggling follow: \(error)")
                await MainActor.run {
                    self.isProcessingFollow = false
                }
            }
        }
    }
}

class BasicFollowListViewModel: ObservableObject {
    @Published var users: [UserProfile] = []
    @Published var isLoading = false
    
    private var db = Firestore.firestore()
    
    func loadUsers(userId: String, listType: FollowListType) {
        isLoading = true
        
        // Use the userFollows collection
        let query = listType == .followers 
            ? db.collection("userFollows").whereField("followeeId", isEqualTo: userId)
            : db.collection("userFollows").whereField("followerId", isEqualTo: userId)
        
        query.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching follow relationships: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
                return
            }
            
            guard let documents = snapshot?.documents else {
                DispatchQueue.main.async {
                    self.users = []
                    self.isLoading = false
                }
                return
            }
            
            // Extract user IDs based on the list type
            let userIds = documents.compactMap { doc -> String? in
                let data = doc.data()
                return listType == .followers 
                    ? data["followerId"] as? String 
                    : data["followeeId"] as? String
            }
            
            if userIds.isEmpty {
                DispatchQueue.main.async {
                    self.users = []
                    self.isLoading = false
                }
                return
            }
            
            self.fetchUserProfiles(userIds: userIds)
        }
    }
    
    private func fetchUserProfiles(userIds: [String]) {
        guard !userIds.isEmpty else {
            DispatchQueue.main.async {
                self.users = []
                self.isLoading = false
            }
            return
        }
        
        // Batch requests for Firestore 'in' query limit of 10
        let batches = userIds.chunked(into: 10)
        var allUsers: [UserProfile] = []
        let dispatchGroup = DispatchGroup()
        
        for batch in batches {
            dispatchGroup.enter()
            
            db.collection("users").whereField(FieldPath.documentID(), in: batch)
                .getDocuments { (querySnapshot, error) in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("Error fetching user profiles: \(error.localizedDescription)")
                        return
                    }

                    guard let documents = querySnapshot?.documents else {
                        return
                    }

                    let batchUsers = documents.compactMap { queryDocumentSnapshot -> UserProfile? in
                        do {
                            return try UserProfile(dictionary: queryDocumentSnapshot.data(), id: queryDocumentSnapshot.documentID)
                        } catch {
                            print("Error creating UserProfile from document: \(error)")
                            return nil
                        }
                    }
                    
                    allUsers.append(contentsOf: batchUsers)
                }
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            // Sort users alphabetically
            allUsers.sort {
                ($0.displayName ?? $0.username).lowercased() < ($1.displayName ?? $1.username).lowercased()
            }
            
            self.users = allUsers
            self.isLoading = false
        }
    }
}

