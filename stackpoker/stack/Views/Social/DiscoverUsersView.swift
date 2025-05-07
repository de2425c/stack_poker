import SwiftUI
import FirebaseFirestore

struct DiscoverUsersView: View {
    let userId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = DiscoverUsersViewModel()
    @EnvironmentObject var userService: UserService
    @State private var searchText = ""
    
    var body: some View {
        NavigationView {
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
                                viewModel.searchUsers(query: newValue)
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.top)
                    
                    if searchText.isEmpty {
                        // Show suggested users to follow
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Suggested Users")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                    .padding(.top, 20)
                                
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.top, 40)
                                } else if viewModel.suggestedUsers.isEmpty {
                                    Text("No suggestions available")
                                        .foregroundColor(.gray)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.top, 40)
                                } else {
                                    LazyVStack(spacing: 0) {
                                        ForEach(viewModel.suggestedUsers) { user in
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
                    } else {
                        // Show search results
                        if viewModel.isLoading {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                            Spacer()
                        } else if viewModel.searchResults.isEmpty {
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
                    }
                }
            }
            .navigationTitle("Discover Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .onAppear {
            viewModel.fetchSuggestedUsers(currentUserId: userId)
        }
    }
}

class DiscoverUsersViewModel: ObservableObject {
    @Published var suggestedUsers: [UserProfile] = []
    @Published var searchResults: [UserProfile] = []
    @Published var isLoading = false
    private var db = Firestore.firestore()
    private var searchDebounceTimer: Timer?
    
    func fetchSuggestedUsers(currentUserId: String) {
        isLoading = true
        
        // First get the current user's following list
        db.collection("users").document(currentUserId).collection("following")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error fetching following list: \(error)")
                    self.isLoading = false
                    return
                }
                
                let followingIds = snapshot?.documents.map { $0.documentID } ?? []
                
                // Now fetch users not in this list (exclude the current user too)
                var excludeIds = followingIds
                excludeIds.append(currentUserId)
                
                // Since Firestore doesn't support "not in" queries directly,
                // we'll fetch a limited number of users and filter on the client side
                self.db.collection("users")
                    .limit(to: 50)
                    .getDocuments { [weak self] snapshot, error in
                        guard let self = self else { return }
                        
                        if let error = error {
                            print("Error fetching users: \(error)")
                            self.isLoading = false
                            return
                        }
                        
                        let fetchedUsers = snapshot?.documents.compactMap { doc -> UserProfile? in
                            if excludeIds.contains(doc.documentID) {
                                return nil // Skip users we're already following or self
                            }
                            
                            do {
                                return try UserProfile(dictionary: doc.data(), id: doc.documentID)
                            } catch {
                                print("Error parsing user: \(error)")
                                return nil
                            }
                        } ?? []
                        
                        // Limit to 20 random users for variety
                        let randomUsers = Array(fetchedUsers.shuffled().prefix(20))
                        
                        DispatchQueue.main.async {
                            self.suggestedUsers = randomUsers
                            self.isLoading = false
                        }
                    }
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
            
            // Search for users where username or displayName contains the query
            let queryLower = query.lowercased()
            
            // We'll perform two separate queries and combine results
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
} 