import SwiftUI
import FirebaseFirestore

enum FollowListType {
    case followers
    case following
}

struct FollowListView: View {
    let userId: String
    let listType: FollowListType
    @StateObject private var viewModel = FollowListViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @EnvironmentObject var userService: UserService
    
    private var loggedInUserId: String? {
        userService.currentUserProfile?.id
    }
    
    var body: some View {
        ZStack {
            Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search users", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                        .onChange(of: searchText) { newValue in
                            if listType == .following {
                                viewModel.searchUsers(query: newValue)
                            } else {
                                viewModel.filterUsers(searchText: newValue)
                            }
                        }
                }
                .padding(12)
                .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.top)
                
                if viewModel.isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                    Spacer()
                } else if listType == .following && !searchText.isEmpty {
                    // Show search results for following view
                    if viewModel.searchResults.isEmpty {
                        Spacer()
                        Text("No users found")
                            .foregroundColor(.gray)
                            .padding(.top, 40)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.searchResults) { userInRow in
                                    UserListRow(
                                        user: userInRow,
                                        profileOwnerUserId: userId,
                                        loggedInUserId: loggedInUserId
                                    )
                                    .environmentObject(userService)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                } else {
                    // Show followers or current following
                    if viewModel.users.isEmpty {
                        Spacer()
                        Text(listType == .followers ? "No followers yet" : "Not following anyone")
                            .foregroundColor(.gray)
                            .padding(.top, 40)
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.filteredUsers) { userInRow in
                                    UserListRow(
                                        user: userInRow,
                                        profileOwnerUserId: userId,
                                        loggedInUserId: loggedInUserId
                                    )
                                    .environmentObject(userService)
                                    .padding(.horizontal)
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding(.top, 12)
                        }
                    }
                }
            }
            .navigationTitle(listType == .followers ? "Followers" : "Following")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            viewModel.loadUsers(userId: userId, listType: listType)
        }
    }
}

struct UserListRow: View {
    let user: UserProfile
    let profileOwnerUserId: String
    let loggedInUserId: String?
    @State private var isFollowing = false
    @State private var isLoading = false
    @EnvironmentObject var userService: UserService
    private let followService = FollowService()
    
    private var shouldShowFollowButton: Bool {
        guard let actualLoggedInUserId = loggedInUserId else { return false }
        return user.id != actualLoggedInUserId
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Profile Image
            if let url = user.avatarURL, let imageURL = URL(string: url) {
                ProfileImageView(url: imageURL)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.fill")
                            .foregroundColor(.gray)
                    )
            }
            
            // User Info
            VStack(alignment: .leading, spacing: 4) {
                if let displayName = user.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Text("@\(user.username)")
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                } else {
                    Text(user.username)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                }
                
                if let bio = user.bio {
                    Text(bio)
                        .foregroundColor(.gray)
                        .font(.system(size: 14))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Follow Button (if not the logged-in user themselves)
            if shouldShowFollowButton {
                Button(action: toggleFollow) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: isFollowing ? .white : .black))
                            .frame(width: 20, height: 20)
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
                .disabled(isLoading || loggedInUserId == nil)
            }
        }
        .onAppear {
            checkFollowStatus()
        }
    }
    
    private func checkFollowStatus() {
        guard let actualLoggedInUserId = loggedInUserId, user.id != actualLoggedInUserId else {
            return
        }
        
        Task {
            do {
                isFollowing = try await followService.checkIfFollowing(currentUserId: actualLoggedInUserId, targetUserId: user.id)
            } catch {
                print("Error checking follow status for user \(user.id) by loggedInUser \(actualLoggedInUserId): \(error)")
            }
        }
    }
    
    private func toggleFollow() {
        guard !isLoading, let actualLoggedInUserId = loggedInUserId else { return }
        
        isLoading = true
        
        Task {
            do {
                if isFollowing {
                    try await followService.unfollowUser(currentUserId: actualLoggedInUserId, targetUserId: user.id)
                } else {
                    try await followService.followUser(currentUserId: actualLoggedInUserId, targetUserId: user.id)
                }
                
                try await userService.fetchUserProfile()
                
                withAnimation {
                    isFollowing.toggle()
                }
            } catch {
                print("Error toggling follow state for user \(user.id) by loggedInUser \(actualLoggedInUserId): \(error)")
            }
            isLoading = false
        }
    }
}

class FollowListViewModel: ObservableObject {
    @Published var users: [UserProfile] = []
    @Published var filteredUsers: [UserProfile] = []
    @Published var searchResults: [UserProfile] = []
    @Published var isLoading = false
    private var db = Firestore.firestore()
    private var searchDebounceTimer: Timer?
    
    func loadUsers(userId: String, listType: FollowListType) {
        isLoading = true
        let followsCollection = listType == .followers ? "followers" : "following"
        
        db.collection("users").document(userId).collection(followsCollection)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error fetching follow list for user \(userId): \(error)")
                    self.isLoading = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("No follow documents found for user \(userId) in \(followsCollection)")
                    self.isLoading = false
                    self.users = []
                    self.filteredUsers = []
                    return
                }
                
                let userIds = documents.map { $0.documentID }
                
                if userIds.isEmpty {
                    print("User ID list is empty for user \(userId) in \(followsCollection)")
                    self.users = []
                    self.filteredUsers = []
                    self.isLoading = false
                    return
                }
                
                self.fetchUserProfiles(userIds: userIds)
            }
    }
    
    private func fetchUserProfiles(userIds: [String]) {
        guard !userIds.isEmpty else {
            self.users = []
            self.filteredUsers = []
            self.isLoading = false
            return
        }
        
        db.collection("users").whereField(FieldPath.documentID(), in: userIds)
            .getDocuments { [weak self] (querySnapshot, error) in
                guard let self = self else { return }
                defer { self.isLoading = false }

                if let error = error {
                    print("Error fetching user profiles: \(error.localizedDescription)")
                    self.users = []
                    self.filteredUsers = []
                    return
                }

                guard let documents = querySnapshot?.documents else {
                    print("No documents found for user profiles.")
                    self.users = []
                    self.filteredUsers = []
                    return
                }

                self.users = documents.compactMap { queryDocumentSnapshot -> UserProfile? in
                    try? UserProfile(dictionary: queryDocumentSnapshot.data(), id: queryDocumentSnapshot.documentID)
                }
                self.users.sort {
                    ($0.displayName ?? $0.username).lowercased() < ($1.displayName ?? $1.username).lowercased()
                }
                self.filteredUsers = self.users
                print("Successfully fetched \(self.users.count) user profiles.")
            }
    }
    
    func filterUsers(searchText: String) {
        if searchText.isEmpty {
            filteredUsers = users
        } else {
            let lowercasedQuery = searchText.lowercased()
            filteredUsers = users.filter { user in
                (user.displayName?.lowercased().contains(lowercasedQuery) ?? false) ||
                user.username.lowercased().contains(lowercasedQuery)
            }
        }
    }
    
    func searchUsers(query: String) {
        if query.isEmpty {
            searchResults = []
        } else {
            let lowercasedQuery = query.lowercased()
            searchResults = users.filter { user in
                (user.displayName?.lowercased().contains(lowercasedQuery) ?? false) ||
                user.username.lowercased().contains(lowercasedQuery)
            }
        }
    }
} 