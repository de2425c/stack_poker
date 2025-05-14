import SwiftUI
import Kingfisher
import Foundation

struct UserSearchResultsView: View {
    let searchResults: [UserProfile]
    let isSearching: Bool
    let errorMessage: String?
    let onFollowUser: (String) -> Void
    
    @EnvironmentObject var userService: UserService
    
    var body: some View {
        VStack {
            // Loading state
            if isSearching {
                VStack(spacing: 15) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                        .scaleEffect(1.3)
                    
                    Text("Searching...")
                        .foregroundColor(.gray)
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Error message
            else if let error = errorMessage {
                VStack(spacing: 15) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    
                    Text(error)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // No results
            else if searchResults.isEmpty {
                VStack(spacing: 15) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    
                    Text("No users found")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Results list
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(searchResults) { user in
                            UserResultRow(user: user, onFollowUser: onFollowUser)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                                .background(Color.clear)
                            
                            Divider()
                                .background(Color.gray.opacity(0.3))
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
}

struct UserResultRow: View {
    let user: UserProfile
    let onFollowUser: (String) -> Void
    
    @EnvironmentObject var userService: UserService
    @State private var isFollowing: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // User avatar
            if let photoURL = user.avatarURL, !photoURL.isEmpty {
                KFImage(URL(string: photoURL))
                    .placeholder {
                        Image(systemName: "person.circle")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                    }
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.gray)
                    .frame(width: 50, height: 50)
            }
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let displayName = user.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Text(user.username)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    if let isVerified = user.isVerified, isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                            .font(.system(size: 12))
                    }
                }
                
                Text("@\(user.username)")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                
                if let bio = user.bio, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Follow button
            Button(action: {
                onFollowUser(user.id)
                isFollowing.toggle() // Optimistic UI update
            }) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
                    .background(
                        isFollowing ?
                        RoundedRectangle(cornerRadius: 15).stroke(Color.gray, lineWidth: 1) :
                        RoundedRectangle(cornerRadius: 15).fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                    )
                    .foregroundColor(isFollowing ? .white : .black)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .onAppear {
            checkIfFollowing()
        }
    }
    
    private func checkIfFollowing() {
        Task {
            isFollowing = await userService.isFollowing(userId: user.id)
        }
    }
}

struct UserSearchResultsView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            UserSearchResultsView(
                searchResults: [
                    UserProfile(
                        id: "1", 
                        username: "johndoe", 
                        displayName: "John Doe", 
                        createdAt: Date(), 
                        bio: "iOS Developer", 
                        avatarURL: nil,
                        isFollowing: false
                    ),
                    UserProfile(
                        id: "2", 
                        username: "janedoe", 
                        displayName: "Jane Doe", 
                        createdAt: Date(), 
                        bio: "UX Designer with a passion for creating intuitive user experiences. Based in San Francisco.", 
                        avatarURL: nil,
                        isFollowing: false
                    )
                ],
                isSearching: false,
                errorMessage: nil,
                onFollowUser: { _ in }
            )
            .environmentObject(UserService())
        }
    }
} 
