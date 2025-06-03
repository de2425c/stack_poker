import SwiftUI
import Combine
import FirebaseFirestore
import Kingfisher

@MainActor
class UserSearchViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var searchResults: [UserProfile] = []
    @Published var isLoading = false
    @Published var searchHasBeenPerformed = false

    private var userService: UserService
    private var searchDebounceTimer: AnyCancellable?
    private let db = Firestore.firestore()

    init(userService: UserService) {
        self.userService = userService
        
        searchDebounceTimer = $searchText
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self?.searchUsers(query: query)
                } else {
                    self?.searchResults = []
                    // Don't reset searchHasBeenPerformed here, 
                    // so "Enter a name..." prompt can show if user clears text after a search.
                }
            }
    }

    func searchUsers(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        searchHasBeenPerformed = true
        
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryLower = trimmedQuery.lowercased()
        let currentUserId = userService.currentUserProfile?.id
        
        Task {
            do {
                var allResults: [UserProfile] = []
                
                // Search with both original case and lowercase to handle case sensitivity issues
                let searchVariants = [trimmedQuery, queryLower, trimmedQuery.capitalized]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                // Remove duplicates from search variants
                let uniqueSearchVariants = Array(Set(searchVariants))
                
                // Search by username with different case variants
                for searchVariant in uniqueSearchVariants {
                    let usernameResults = try await self.searchByField("username", query: searchVariant, currentUserId: currentUserId)
                    
                    // Add results that aren't already in our list
                    for result in usernameResults {
                        if !allResults.contains(where: { $0.id == result.id }) {
                            allResults.append(result)
                        }
                    }
                }
                
                // Search by displayName with different case variants
                for searchVariant in uniqueSearchVariants {
                    let displayNameResults = try await self.searchByField("displayName", query: searchVariant, currentUserId: currentUserId)
                    
                    // Add results that aren't already in our list
                    for result in displayNameResults {
                        if !allResults.contains(where: { $0.id == result.id }) {
                            allResults.append(result)
                        }
                    }
                }
                
                // Client-side filtering for better substring matching
                let filteredResults = allResults.filter { profile in
                    let username = profile.username.lowercased()
                    let displayName = (profile.displayName ?? "").lowercased()
                    let searchLower = queryLower
                    
                    return username.contains(searchLower) || displayName.contains(searchLower)
                }
                
                // Sort results by relevance (exact matches first, then starts with, then contains)
                let sortedResults = filteredResults.sorted { profile1, profile2 in
                    let name1 = (profile1.displayName ?? profile1.username).lowercased()
                    let name2 = (profile2.displayName ?? profile2.username).lowercased()
                    let username1 = profile1.username.lowercased()
                    let username2 = profile2.username.lowercased()
                    
                    // Exact matches first
                    let exact1 = name1 == queryLower || username1 == queryLower
                    let exact2 = name2 == queryLower || username2 == queryLower
                    if exact1 != exact2 { return exact1 }
                    
                    // Then starts with
                    let starts1 = name1.hasPrefix(queryLower) || username1.hasPrefix(queryLower)
                    let starts2 = name2.hasPrefix(queryLower) || username2.hasPrefix(queryLower)
                    if starts1 != starts2 { return starts1 }
                    
                    // Finally alphabetical
                    return name1 < name2
                }
                
                await MainActor.run {
                    self.searchResults = Array(sortedResults.prefix(10))
                    self.isLoading = false
                }
                
            } catch {
                print("Search error: \(error)")
                await MainActor.run {
                    self.searchResults = []
                    self.isLoading = false
                }
            }
        }
    }
    
    private func searchByField(_ field: String, query: String, currentUserId: String?) async throws -> [UserProfile] {
        var results: [UserProfile] = []
        
        // Firestore prefix search
        let snapshot = try await db.collection("users")
            .whereField(field, isGreaterThanOrEqualTo: query)
            .whereField(field, isLessThanOrEqualTo: query + "\u{f8ff}")
            .limit(to: 20) // Get more results for better filtering
            .getDocuments()
        
        for document in snapshot.documents {
            if let profile = try? UserProfile(dictionary: document.data(), id: document.documentID) {
                if profile.id != currentUserId {
                    results.append(profile)
                }
            }
        }
        
        return results
    }
    
    func clearSearch() {
        searchText = ""
        searchResults = []
        // Keep searchHasBeenPerformed true if user clears after searching
        isLoading = false
    }
}

// Breaking up complex views into smaller components
struct SearchBarView: View {
    @Binding var text: String
    var onClear: () -> Void
    var focusedField: FocusState<Bool>.Binding // Changed to correct binding type
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundColor(Color.gray.opacity(0.8))
            
            TextField("Find people by name or username...", text: $text)
                .font(.system(size: 16))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .focused(focusedField) // Use the binding directly
            
            if !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.gray.opacity(0.8))
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal)
        .padding(.top, 5) //keep this
        .padding(.bottom, 12)
    }
}

struct LoadingStateView: View {
    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                    .scaleEffect(1.2)
            }
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.gray.opacity(0.9))
                .padding(.top, 8)
            Spacer()
        }
    }
}

struct NoResultsView: View {
    let searchText: String
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No users found for\n\"\(searchText)\"")
                .font(.headline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

struct EmptyPromptView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("Enter a name or username\nto find people to follow")
                .font(.headline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
}

struct SearchResultsView: View {
    let users: [UserProfile]
    let currentUserId: String
    let userService: UserService // Passed from parent
    let onUserTapped: (UserProfile) -> Void // NEW callback

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(users) { user in
                    Button(action: { onUserTapped(user) }) {
                        EnhancedUserRow(user: user, currentUserId: currentUserId, userService: userService)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.2))
                            .cornerRadius(8)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 10)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// The dedicated User Search View (to be presented as a sheet)
struct UserSearchView: View {
    @StateObject private var viewModel: UserSearchViewModel
    @EnvironmentObject var passedUserService: UserService
    @Environment(\.dismiss) var dismiss
    @FocusState private var isSearchFieldFocused: Bool // For keyboard focus
    @State private var animateBackground = false
    let currentUserId: String
    let onUserSelected: (String) -> Void // NEW callback

    init(currentUserId: String, userService: UserService, onUserSelected: @escaping (String) -> Void) {
        self.currentUserId = currentUserId
        self.onUserSelected = onUserSelected
        _viewModel = StateObject(wrappedValue: UserSearchViewModel(userService: userService))
    }
    
    // Extract complex background logic to reduce complexity
    private var backgroundView: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
                .opacity(0.9) // Slightly dim the background

            // Subtle animated gradient overlay for visual interest
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(UIColor(red: 5/255, green: 5/255, blue: 10/255, alpha: 0.4)),
                    Color(UIColor(red: 20/255, green: 20/255, blue: 30/255, alpha: 0.3))
                ]),
                startPoint: animateBackground ? .topLeading : .bottomLeading,
                endPoint: animateBackground ? .bottomTrailing : .topTrailing
            )
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                animateBackground.toggle()
            }
        }
    }
    
    // Extract content display logic to reduce complexity
    @ViewBuilder
    private var contentView: some View {
        ZStack {
            // Background for content area
            Color.black.opacity(0.2)
                .cornerRadius(12)
                .edgesIgnoringSafeArea(.bottom)
            
            if viewModel.isLoading {
                LoadingStateView()
                    .transition(.opacity)
            }
            else if viewModel.searchResults.isEmpty && viewModel.searchHasBeenPerformed && !viewModel.searchText.isEmpty {
                NoResultsView(searchText: viewModel.searchText)
                    .transition(.opacity)
            }
            else if (viewModel.searchResults.isEmpty && !viewModel.searchHasBeenPerformed) || 
                    (viewModel.searchText.isEmpty && viewModel.searchResults.isEmpty) {
                EmptyPromptView()
                    .transition(.opacity)
            }
            else if !viewModel.searchResults.isEmpty {
                SearchResultsView(
                    users: viewModel.searchResults,
                    currentUserId: currentUserId,
                    userService: passedUserService,
                    onUserTapped: { user in
                        onUserSelected(user.id)
                        dismiss() // Close search view before navigating
                    }
                )
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar Input
                SearchBarView(
                    text: $viewModel.searchText,
                    onClear: viewModel.clearSearch,
                    focusedField: $isSearchFieldFocused // Pass the FocusState binding directly
                )
                
                // Search Results/States Area
                contentView
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isSearchFieldFocused = false
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                }
            }
            .onAppear {
                // Focus the text field when the view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isSearchFieldFocused = true
                }
            }
            // Attach background to the entire NavigationView instead of using a ZStack
            .background(backgroundView)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .environmentObject(passedUserService)
    }
}

// Enhanced User Row with better visuals
struct EnhancedUserRow: View {
    let user: UserProfile
    let currentUserId: String
    @ObservedObject var userService: UserService
    @State private var isFollowing: Bool = false
    @State private var processingFollow: Bool = false
    @State private var animateFollow = false
    @State private var hasCheckedFollowStatus = false
    
    var body: some View {
        HStack(spacing: 16) {
            // User Avatar - Enhanced version
            Group {
                if let avatarUrl = user.avatarURL, let url = URL(string: avatarUrl) {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            PlaceholderAvatarView(size: 50)
                        }
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                } else {
                    PlaceholderAvatarView(size: 50)
                }
            }
            
            // User Info - Enhanced version
            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName ?? user.username)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("@\(user.username)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray.opacity(0.8))
                
                // Optional: Show bio snippet if available
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio.prefix(40) + (bio.count > 40 ? "..." : ""))
                        .font(.system(size: 12))
                        .foregroundColor(.gray.opacity(0.7))
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Follow Button - Enhanced version
            if user.id != currentUserId {
                Button(action: toggleFollow) {
                    Group {
                        if processingFollow {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: isFollowing ? .white.opacity(0.9) : .black))
                                    .scaleEffect(0.8)
                                Text(isFollowing ? "Unfollowing..." : "Following...")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isFollowing ? .white.opacity(0.9) : .black)
                            }
                        } else {
                            Text(isFollowing ? "Following" : "Follow")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(isFollowing ? .white.opacity(0.9) : .black)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(followButtonBackground)
                }
                .disabled(processingFollow)
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .contentShape(Rectangle()) // Make tapping easier
        .onAppear {
            if !hasCheckedFollowStatus {
                checkIfFollowing()
            }
        }
        .onChange(of: user.id) { _ in
            // Reset state when user changes
            hasCheckedFollowStatus = false
            isFollowing = false
            processingFollow = false
            checkIfFollowing()
        }
    }
    
    // Extract complex button background to reduce complexity
    private var followButtonBackground: some View {
        Capsule()
            .fill(isFollowing 
                   ? Color.gray.opacity(0.4)
                   : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
            .scaleEffect(animateFollow ? 0.95 : 1.0)
            .shadow(color: isFollowing 
                    ? Color.black.opacity(0.1) 
                    : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3)),
                    radius: 4, x: 0, y: 2)
    }

    private func checkIfFollowing() {
        guard user.id != currentUserId, !hasCheckedFollowStatus else { return }
        processingFollow = true
        hasCheckedFollowStatus = true
        
        Task {
            let followStatus = await userService.isUserFollowing(targetUserId: user.id, currentUserId: currentUserId)
            await MainActor.run {
                self.isFollowing = followStatus
                self.processingFollow = false
            }
        }
    }

    private func toggleFollow() {
        guard user.id != currentUserId, !processingFollow else { return }
        processingFollow = true
        
        // Add button press animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            animateFollow = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    animateFollow = false
                }
            }
        }
        
        Task {
            do {
                if isFollowing {
                    try await userService.unfollowUser(userIdToUnfollow: user.id)
                    await MainActor.run {
                        self.isFollowing = false
                    }
                } else {
                    try await userService.followUser(userIdToFollow: user.id)
                    await MainActor.run {
                        self.isFollowing = true
                    }
                }
            } catch {
                print("Error toggling follow: \(error)")
                // Revert the optimistic update if there was an error
                // The follow status will be re-checked on next appear
                await MainActor.run {
                    self.hasCheckedFollowStatus = false
                }
            }
            
            await MainActor.run {
                self.processingFollow = false
            }
        }
    }
}

// Keep the original UserRow for compatibility if needed elsewhere
struct UserRow: View {
    let user: UserProfile
    let currentUserId: String
    @ObservedObject var userService: UserService
    @State private var isFollowing: Bool = false
    @State private var processingFollow: Bool = false
    
    var body: some View {
        HStack {
            Group {
                if let avatarUrl = user.avatarURL, let url = URL(string: avatarUrl) {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            PlaceholderAvatarView(size: 40)
                        }
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    PlaceholderAvatarView(size: 40)
                }
            }
            
            VStack(alignment: .leading) {
                Text(user.displayName ?? user.username)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("@\(user.username)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            if user.id != currentUserId {
                Button(action: toggleFollow) {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isFollowing ? .white : .black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isFollowing ? Color.gray.opacity(0.4) : Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .cornerRadius(16)
                }
                .disabled(processingFollow)
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            checkIfFollowing()
        }
    }

    private func checkIfFollowing() {
        guard user.id != currentUserId else { return }
        processingFollow = true
        Task {
            self.isFollowing = await userService.isUserFollowing(targetUserId: user.id, currentUserId: currentUserId)
            processingFollow = false
        }
    }

    private func toggleFollow() {
        guard user.id != currentUserId else { return }
        processingFollow = true
        Task {
            do {
                if isFollowing {
                    try await userService.unfollowUser(userIdToUnfollow: user.id)
                } else {
                    try await userService.followUser(userIdToFollow: user.id)
                }
                self.isFollowing.toggle() 
            } catch {

            }
            processingFollow = false
        }
    }
} 