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
                                ForEach(viewModel.searchResults) { user in
                                    UserListRow(user: user, currentUserId: userId)
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
                                ForEach(viewModel.filteredUsers) { user in
                                    UserListRow(user: user, currentUserId: userId)
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
    let currentUserId: String
    @State private var isFollowing = false
    @State private var isLoading = false
    @EnvironmentObject var userService: UserService
    private let followService = FollowService()
    
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
            
            // Follow Button (if not current user)
            if user.id != currentUserId {
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
                .disabled(isLoading)
            }
        }
        .onAppear {
            checkFollowStatus()
        }
    }
    
    private func checkFollowStatus() {
        Task {
            do {
                isFollowing = try await followService.checkIfFollowing(currentUserId: currentUserId, targetUserId: user.id)
            } catch {
                print("Error checking follow status: \(error)")
            }
        }
    }
    
    private func toggleFollow() {
        guard !isLoading else { return }
        isLoading = true
        
        Task {
            do {
                if isFollowing {
                    try await followService.unfollowUser(currentUserId: currentUserId, targetUserId: user.id)
                } else {
                    try await followService.followUser(currentUserId: currentUserId, targetUserId: user.id)
                }
                
                // Refresh the current user's profile to update counts
                try await userService.fetchUserProfile()
                
                withAnimation {
                    isFollowing.toggle()
                }
            } catch {
                print("Error toggling follow status: \(error)")
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
        
        // First get the list of follower/following IDs
        db.collection("users").document(userId).collection(followsCollection)
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error fetching follow list: \(error)")
                    self.isLoading = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.isLoading = false
                    return
                }
                
                // Get all user IDs from the follow collection
                let userIds = documents.map { $0.documentID }
                
                if userIds.isEmpty {
                    self.users = []
                    self.filteredUsers = []
                    self.isLoading = false
                    return
                }
                
                // Fetch user profiles for all IDs
                self.fetchUserProfiles(userIds: userIds)
            }
    }
    
    private func fetchUserProfiles(userIds: [String]) {
        let group = DispatchGroup()
        var fetchedUsers: [UserProfile] = []
        
        for userId in userIds {
            group.enter()
            
            db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
                defer { group.leave() }
                guard let self = self else { return }
                
                if let error = error {
                    print("Error fetching user profile: \(error)")
                    return
                }
                
                if let data = snapshot?.data(),
                   let profile = try? UserProfile(dictionary: data, id: userId) {
                    fetchedUsers.append(profile)
                }
            }
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.users = fetchedUsers.sorted { $0.username < $1.username }
            self.filteredUsers = self.users
            self.isLoading = false
        }
    }
    
    func searchUsers(query: String) {
        // Cancel any existing search timer
        searchDebounceTimer?.invalidate()
        
        // If query is empty, clear search results
        if query.isEmpty {
            self.searchResults = []
            return
        }
        
        // Debounce the search to avoid too many Firestore queries
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            self.isLoading = true
            let queryLower = query.lowercased()
            
            // We'll perform two separate queries (username and displayName) and combine results
            let dispatchGroup = DispatchGroup()
            var combinedResults: [UserProfile] = []
            
            // Query by username
            dispatchGroup.enter()
            db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: queryLower)
                .whereField("username", isLessThanOrEqualTo: queryLower + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments { [weak self] snapshot, error in
                    defer { dispatchGroup.leave() }
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Error searching users by username: \(error)")
                        return
                    }
                    
                    for document in snapshot?.documents ?? [] {
                        if let profile = try? UserProfile(dictionary: document.data(), id: document.documentID) {
                            combinedResults.append(profile)
                        }
                    }
                }
            
            // Query by displayName
            dispatchGroup.enter()
            db.collection("users")
                .whereField("displayName", isGreaterThanOrEqualTo: queryLower)
                .whereField("displayName", isLessThanOrEqualTo: queryLower + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments { [weak self] snapshot, error in
                    defer { dispatchGroup.leave() }
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("Error searching users by displayName: \(error)")
                        return
                    }
                    
                    for document in snapshot?.documents ?? [] {
                        if let profile = try? UserProfile(dictionary: document.data(), id: document.documentID) {
                            // Only add if not already in results (to avoid duplicates)
                            if !combinedResults.contains(where: { $0.id == profile.id }) {
                                combinedResults.append(profile)
                            }
                        }
                    }
                }
            
            dispatchGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                self.searchResults = combinedResults.sorted { 
                    // Sort by displayName or username if displayName is nil
                    let name1 = $0.displayName ?? $0.username
                    let name2 = $1.displayName ?? $1.username
                    return name1 < name2
                }
                self.isLoading = false
            }
        }
    }
    
    func filterUsers(searchText: String) {
        if searchText.isEmpty {
            filteredUsers = users
        } else {
            let query = searchText.lowercased()
            filteredUsers = users.filter { user in
                // Check username
                let usernameMatch = user.username.lowercased().contains(query)
                
                // Check display name if available
                let displayNameMatch = user.displayName?.lowercased().contains(query) ?? false
                
                // Check bio if available
                let bioMatch = user.bio?.lowercased().contains(query) ?? false
                
                return usernameMatch || displayNameMatch || bioMatch
            }
        }
    }
} 