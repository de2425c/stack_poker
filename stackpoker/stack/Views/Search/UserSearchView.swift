import SwiftUI
import Combine
import FirebaseFirestore
import Kingfisher

// ViewModel remains largely the same
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

    // Search logic is designed to fetch up to 10 unique users 
    // by combining results from username and displayName queries.
    // If fewer are returned, it's due to the search term or available data.
    func searchUsers(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        searchHasBeenPerformed = true
        
        let queryLower = query.lowercased()
        let dispatchGroup = DispatchGroup()
        var combinedResults: [UserProfile] = []
        let currentUserId = userService.currentUserProfile?.id

        // Query by username
        dispatchGroup.enter()
        db.collection("users")
            .whereField("username", isGreaterThanOrEqualTo: queryLower)
            .whereField("username", isLessThanOrEqualTo: queryLower + "\u{f8ff}")
            .limit(to: 10) // Firestore query limit for this part
            .getDocuments { snapshot, error in
                defer { dispatchGroup.leave() }
                if let error = error {
                    print("Error searching users by username: \(error)")
                    return
                }
                for document in snapshot?.documents ?? [] {
                    if let profile = try? UserProfile(dictionary: document.data(), id: document.documentID) {
                        if profile.id != currentUserId {
                           combinedResults.append(profile)
                        }
                    }
                }
            }
        
        // Query by displayName
        dispatchGroup.enter()
        db.collection("users")
            .whereField("displayName", isGreaterThanOrEqualTo: queryLower)
            .whereField("displayName", isLessThanOrEqualTo: queryLower + "\u{f8ff}")
            .limit(to: 10) // Firestore query limit for this part
            .getDocuments { snapshot, error in
                defer { dispatchGroup.leave() }
                if let error = error {
                    print("Error searching users by displayName: \(error)")
                    return
                }
                for document in snapshot?.documents ?? [] {
                    if let profile = try? UserProfile(dictionary: document.data(), id: document.documentID) {
                        if profile.id != currentUserId {
                            // Add only if not already present from username search
                            if !combinedResults.contains(where: { $0.id == profile.id }) {
                                combinedResults.append(profile)
                            }
                        }
                    }
                }
            }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            // Sort and limit total results to 10 unique users
            self?.searchResults = Array(combinedResults.sorted {
                ($0.displayName ?? $0.username).lowercased() < ($1.displayName ?? $1.username).lowercased()
            }.prefix(10))
            self?.isLoading = false
        }
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
        .padding(.top, 15)
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
    let userService: UserService // Changed to let rather than @EnvironmentObject
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(users) { user in
                    EnhancedUserRow(user: user, currentUserId: currentUserId, userService: userService)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.2))
                        .cornerRadius(8)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
            }
            .padding(.vertical, 10)
        }
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

    init(currentUserId: String, userService: UserService) {
        self.currentUserId = currentUserId
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
                    userService: passedUserService // Pass the userService
                )
                .transition(.opacity)
            }
        }
        .padding(.top, 4)
    }

    var body: some View {
        NavigationView { 
            ZStack {
                // Background View
                backgroundView
                
                // Main Content
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
        }
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
    
    var body: some View {
        HStack(spacing: 16) {
            // User Avatar - Enhanced version
            Group {
                if let avatarUrl = user.avatarURL, let url = URL(string: avatarUrl) {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            Circle()
                                .fill(Color(UIColor(red: 20/255, green: 20/255, blue: 25/255, alpha: 1.0)))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.gray.opacity(0.7))
                                )
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
                    Circle()
                        .fill(Color(UIColor(red: 20/255, green: 20/255, blue: 25/255, alpha: 1.0)))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.gray.opacity(0.7))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
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
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isFollowing ? .white.opacity(0.9) : .black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            followButtonBackground
                        )
                }
                .disabled(processingFollow)
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .contentShape(Rectangle()) // Make tapping easier
        .onAppear {
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
                } else {
                    try await userService.followUser(userIdToFollow: user.id)
                }
                self.isFollowing.toggle() 
            } catch {
                print("Error toggling follow state for user \(user.username): \(error)")
            }
            processingFollow = false
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
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 40, height: 40)
                                .foregroundColor(.gray)
                        }
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.gray)
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
                print("Error toggling follow state for user \(user.username): \(error)")
            }
            processingFollow = false
        }
    }
} 