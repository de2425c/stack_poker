import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Kingfisher

// MARK: - Profile Card View (Modified from ProfileContent)
struct ProfileCardView: View {
    let userId: String
    @EnvironmentObject private var userService: UserService
    @Binding var showEdit: Bool
    @Binding var showingFollowersSheet: Bool
    @Binding var showingFollowingSheet: Bool

    var body: some View {
        VStack(spacing: 15) {
                // Try to get the profile from loadedUsers first, fallback to currentUserProfile
                if let profile = userService.loadedUsers[userId] ?? userService.currentUserProfile {
                    VStack(alignment: .leading, spacing: 15) {
                        // Top Section: Avatar, Name, Username, Location, Stats
                        HStack(spacing: 16) {
                        // Profile picture
                            if let url = profile.avatarURL, !url.isEmpty, let imageURL = URL(string: url) {
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                    case .failure(_):
                                        PlaceholderAvatarView(size: 60)
                                    case .empty:
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0))))
                                            .frame(width: 60, height: 60)
                                    @unknown default:
                                        PlaceholderAvatarView(size: 60)
                                    }
                                }
                        } else {
                            PlaceholderAvatarView(size: 60)
                        }
                            
                            // Middle: Name, Username, Location
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName ?? "@\(profile.username)")
                                .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                                if profile.displayName != nil {
                                    Text("@\(profile.username)")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.gray)
                                }
                                if let location = profile.location, !location.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "mappin.and.ellipse")
                                            .font(.system(size: 12))
                                            .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                        Text(location)
                                            .font(.system(size: 13))
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Right: Stats for Followers/Following
                            VStack(alignment: .trailing, spacing: 4) {
                                Button(action: { showingFollowersSheet = true }) {
                                    HStack(spacing: 2) {
                                        Text("\(profile.followersCount)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("followers")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            
                                Button(action: { showingFollowingSheet = true }) {
                                    HStack(spacing: 2) {
                                        Text("\(profile.followingCount)")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                        Text("following")
                                            .font(.system(size: 12))
                                            .foregroundColor(.gray)
                                    }
                                    .padding(5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        // Bio and hyperlink combined
                        VStack(alignment: .leading, spacing: 8) {
                            if let bio = profile.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.85))
                                    .multilineTextAlignment(.leading)
                            }
                            
                            // Simple hyperlink - just colored text
                            if let hyperlinkText = profile.hyperlinkText, !hyperlinkText.isEmpty,
                               let hyperlinkURL = profile.hyperlinkURL, !hyperlinkURL.isEmpty {
                                Button(action: {
                                    // Ensure URL has proper scheme
                                    var urlString = hyperlinkURL
                                    if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
                                        urlString = "https://" + urlString
                                    }
                                    
                                    if let url = URL(string: urlString) {
                                        UIApplication.shared.open(url)
                                    }
                                }) {
                                    Text(hyperlinkText)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.blue)
                                        .underline()
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        // Edit Profile button
                        HStack {
                            Spacer()
                            Button(action: {
                                showEdit = true
                            }) {
                                Text("Edit Profile")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule().fill(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                            .shadow(color: Color.green.opacity(0.3), radius: 3, y: 2)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    )
                } else {
                    // Loading state
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.white))
                        Text("Loading profile...")
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .onAppear {
            // Ensure we have the profile data loaded
            if userService.currentUserProfile == nil {
                Task { try? await userService.fetchUserProfile() }
            }
            // Also ensure we have the user data in loadedUsers for consistency
            if userService.loadedUsers[userId] == nil {
                Task { await userService.fetchUser(id: userId) }
            }
        }
    }
}