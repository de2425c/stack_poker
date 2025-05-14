import Foundation
import FirebaseFirestore
import Combine

@MainActor
class UserSearchService: ObservableObject {
    @Published var searchResults: [UserProfile] = []
    @Published var isSearching: Bool = false
    @Published var errorMessage: String? = nil
    
    private var db = Firestore.firestore()
    private var cancellables = Set<AnyCancellable>()
    
    init() {}
    
    func searchUsers(query: String, currentUserId: String) async {
        // Set searching state
        await MainActor.run {
            self.isSearching = true
            self.errorMessage = nil
        }
        
        // Trim and validate query
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !searchQuery.isEmpty else {
            await MainActor.run {
                self.searchResults = []
                self.isSearching = false
            }
            return
        }
        
        do {
            // Create compound query to search by username OR displayName
            let usernameQuery = db.collection("users")
                .whereField("usernameLowercase", isGreaterThanOrEqualTo: searchQuery)
                .whereField("usernameLowercase", isLessThanOrEqualTo: searchQuery + "\u{f8ff}")
                .limit(to: 20)
            
            let displayNameQuery = db.collection("users")
                .whereField("displayNameLowercase", isGreaterThanOrEqualTo: searchQuery)
                .whereField("displayNameLowercase", isLessThanOrEqualTo: searchQuery + "\u{f8ff}")
                .limit(to: 20)
            
            // Execute both queries and combine results
            async let usernameSnapshot = try usernameQuery.getDocuments()
            async let displayNameSnapshot = try displayNameQuery.getDocuments()
            
            let (usernameResults, displayNameResults) = try await (usernameSnapshot, displayNameSnapshot)
            
            // Process results, removing duplicates and the current user
            var combinedUsers = Set<UserProfile>()
            
            // Add username matches
            for document in usernameResults.documents {
                do {
                    let user = try UserProfile(dictionary: document.data(), id: document.documentID)
                    if user.id != currentUserId {
                        combinedUsers.insert(user)
                    }
                } catch {
                    print("Error parsing user document: \(error)")
                }
            }
            
            // Add display name matches
            for document in displayNameResults.documents {
                do {
                    let user = try UserProfile(dictionary: document.data(), id: document.documentID)
                    if user.id != currentUserId {
                        combinedUsers.insert(user)
                    }
                } catch {
                    print("Error parsing user document: \(error)")
                }
            }
            
            // Sort results (prioritize exact matches, then alphabetically)
            let sortedUsers = combinedUsers.sorted { user1, user2 in
                // Exact username match gets top priority
                if user1.username.lowercased() == searchQuery && user2.username.lowercased() != searchQuery {
                    return true
                }
                if user1.username.lowercased() != searchQuery && user2.username.lowercased() == searchQuery {
                    return false
                }
                
                // Exact display name match gets second priority
                if let displayName1 = user1.displayName?.lowercased(),
                   let displayName2 = user2.displayName?.lowercased(),
                   displayName1 == searchQuery && displayName2 != searchQuery {
                    return true
                }
                if let displayName1 = user1.displayName?.lowercased(),
                   let displayName2 = user2.displayName?.lowercased(),
                   displayName1 != searchQuery && displayName2 == searchQuery {
                    return false
                }
                
                // Otherwise sort alphabetically by username
                return user1.username.lowercased() < user2.username.lowercased()
            }
            
            await MainActor.run {
                self.searchResults = sortedUsers
                self.isSearching = false
            }
        } catch {
            print("Error searching users: \(error)")
            await MainActor.run {
                self.errorMessage = "Something went wrong. Please try again."
                self.isSearching = false
            }
        }
    }
    
    func clearResults() {
        searchResults = []
        errorMessage = nil
    }
} 