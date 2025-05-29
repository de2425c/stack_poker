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
            AppBackgroundView().ignoresSafeArea()
            
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
            .padding(.top, 0)
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
    @State private var navigateToProfile = false
    @EnvironmentObject var userService: UserService
    private let followService = FollowService()
    
    private var shouldShowFollowButton: Bool {
        guard let actualLoggedInUserId = loggedInUserId else { return false }
        return user.id != actualLoggedInUserId
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Tappable profile area (avatar + user info)
            HStack(spacing: 12) {
                // Profile Image
                if let url = user.avatarURL, let imageURL = URL(string: url) {
                    ProfileImageView(url: imageURL)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    PlaceholderAvatarView(size: 50)
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
            }
            .contentShape(Rectangle())
            .onTapGesture {
                navigateToProfile = true
            }
            
            Spacer()
            
            // Follow Button (separate from clickable area)
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
        .background(
            NavigationLink(
                destination: UserProfileView(userId: user.id).environmentObject(userService),
                isActive: $navigateToProfile,
                label: { EmptyView() }
            )
            .hidden()
        )
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
        
        // Use the new userFollows collection instead of subcollections
        let query = listType == .followers 
            ? db.collection("userFollows").whereField("followeeId", isEqualTo: userId)
            : db.collection("userFollows").whereField("followerId", isEqualTo: userId)
        
        query.getDocuments { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching follow relationships: \(error.localizedDescription)")
                self.isLoading = false
                return
            }
            
            guard let documents = snapshot?.documents else {
                print("No follow documents found")
                self.isLoading = false
                self.users = []
                self.filteredUsers = []
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
                print("No user IDs found in follow relationships")
                self.users = []
                self.filteredUsers = []
                self.isLoading = false
                return
            }
            
            print("Found \(userIds.count) \(listType == .followers ? "followers" : "following") user IDs: \(userIds)")
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
        
        // Firestore 'in' queries are limited to 10 items, so we need to batch them
        let batches = userIds.chunked(into: 10)
        var allUsers: [UserProfile] = []
        let dispatchGroup = DispatchGroup()
        
        for batch in batches {
            dispatchGroup.enter()
            
            db.collection("users").whereField(FieldPath.documentID(), in: batch)
                .getDocuments { [weak self] (querySnapshot, error) in
                    defer { dispatchGroup.leave() }
                    
                    if let error = error {
                        print("Error fetching user profiles: \(error.localizedDescription)")
                        return
                    }

                    guard let documents = querySnapshot?.documents else {
                        print("No user profile documents found for batch: \(batch)")
                        return
                    }

                    let batchUsers = documents.compactMap { queryDocumentSnapshot -> UserProfile? in
                        do {
                            return try UserProfile(dictionary: queryDocumentSnapshot.data(), id: queryDocumentSnapshot.documentID)
                        } catch {
                            print("Error creating UserProfile from document \(queryDocumentSnapshot.documentID): \(error)")
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
            
            print("Successfully fetched \(allUsers.count) user profiles")
            self.users = allUsers
            self.filteredUsers = allUsers
            self.isLoading = false
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