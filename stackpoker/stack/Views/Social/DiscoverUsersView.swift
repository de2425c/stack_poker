import SwiftUI
import FirebaseFirestore

struct DiscoverUsersView: View {
    let userId: String // This is the loggedInUserId
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = DiscoverUsersViewModel()
    @EnvironmentObject var userService: UserService // For UserListRow
    @State private var searchText = ""

    // Search Bar View
    @ViewBuilder
    private var searchBarView: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            TextField("Search users", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .foregroundColor(.white)
                .onChange(of: searchText) { newValue in
                    viewModel.searchUsers(query: newValue, currentUserId: self.userId)
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
    }

    // Suggested Users Section
    @ViewBuilder
    private var suggestedUsersSection: some View {
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
                        ForEach(viewModel.suggestedUsers) { userInRow in
                            UserListRow(
                                user: userInRow,
                                profileOwnerUserId: userInRow.id, // For UserListRow's internal logic
                                loggedInUserId: self.userId      // The actual logged-in user
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

    // Search Results Section
    @ViewBuilder
    private var searchResultsSection: some View {
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
                    ForEach(viewModel.searchResults) { userInRow in
                        UserListRow(
                            user: userInRow,
                            profileOwnerUserId: userInRow.id, // For UserListRow's internal logic
                            loggedInUserId: self.userId      // The actual logged-in user
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

    // Main Content Body
    @ViewBuilder
    private var contentBodyView: some View {
        if searchText.isEmpty {
            suggestedUsersSection
        } else {
            searchResultsSection
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor(red: 10/255, green: 10/255, blue: 15/255, alpha: 1.0)).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    searchBarView
                    contentBodyView
                }
            }
            .navigationTitle("Discover Users")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white) // Keep done button white
                }
            }
        }
        .onAppear {
            // userId here is the current logged-in user's ID
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
        
        db.collection("users").document(currentUserId).collection("following")
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("Error fetching following list: \(error)")
                    self.isLoading = false
                    return
                }
                
                let followingIds = snapshot?.documents.map { $0.documentID } ?? []
                var excludeIds = followingIds
                excludeIds.append(currentUserId)
                
                self.db.collection("users")
                    .limit(to: 50) // Increased limit for better variety before client-side shuffle
                    .getDocuments { [weak self] snapshot, error in
                        guard let self = self else { return }
                        
                        if let error = error {
                            print("Error fetching users: \(error)")
                            self.isLoading = false
                            return
                        }
                        
                        let fetchedUsers = snapshot?.documents.compactMap { doc -> UserProfile? in
                            if excludeIds.contains(doc.documentID) {
                                return nil
                            }
                            do {
                                return try UserProfile(dictionary: doc.data(), id: doc.documentID)
                            } catch {
                                print("Error parsing user: \(error)")
                                return nil
                            }
                        } ?? []
                        
                        let randomUsers = Array(fetchedUsers.shuffled().prefix(20))
                        
                        DispatchQueue.main.async {
                            self.suggestedUsers = randomUsers
                            self.isLoading = false
                        }
                    }
            }
    }
    
    func searchUsers(query: String, currentUserId: String) {
        searchDebounceTimer?.invalidate()
        
        if query.isEmpty {
            self.searchResults = []
            // fetchSuggestedUsers(currentUserId: currentUserId) // Now you can call this if needed
            return
        }
        
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.isLoading = true
            let queryLower = query.lowercased()
            let dispatchGroup = DispatchGroup()
            var combinedResults: [UserProfile] = []

            dispatchGroup.enter()
            self.db.collection("users")
                .whereField("username", isGreaterThanOrEqualTo: queryLower)
                .whereField("username", isLessThanOrEqualTo: queryLower + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments { snapshot, error in
                    defer { dispatchGroup.leave() }
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
            
            dispatchGroup.enter()
            self.db.collection("users")
                .whereField("displayName", isGreaterThanOrEqualTo: queryLower)
                .whereField("displayName", isLessThanOrEqualTo: queryLower + "\u{f8ff}")
                .limit(to: 20)
                .getDocuments { snapshot, error in
                    defer { dispatchGroup.leave() }
                    if let error = error {
                        print("Error searching users by displayName: \(error)")
                        return
                    }
                    for document in snapshot?.documents ?? [] {
                        if let profile = try? UserProfile(dictionary: document.data(), id: document.documentID) {
                            if !combinedResults.contains(where: { $0.id == profile.id }) {
                                combinedResults.append(profile)
                            }
                        }
                    }
                }
            
            dispatchGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                // Use the passed currentUserId to filter
                self.searchResults = combinedResults.filter { $0.id != currentUserId } 
                                       .sorted { ($0.displayName ?? $0.username) < ($1.displayName ?? $1.username) }
                self.isLoading = false
            }
        }
    }
} 