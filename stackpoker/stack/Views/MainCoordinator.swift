import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var userService: UserService
    
    enum AuthState {
        case loading
        case signedOut
        case signedIn
        case emailVerificationRequired
    }
    
    init() {
        self.userService = UserService()
        checkAuthState()
    }
    
    func checkAuthState() {
        if let user = Auth.auth().currentUser {
            print("👤 User is signed in with ID: \(user.uid)")
            
            // Check if email is verified
            if !user.isEmailVerified {
                print("⚠️ Email not verified, showing verification screen")
                DispatchQueue.main.async {
                    self.authState = .emailVerificationRequired
                }
                return
            }
            
            Task {
                do {
                    try await userService.fetchUserProfile()
                    DispatchQueue.main.async {
                        print("✅ Profile found, setting state to signedIn")
                        self.authState = .signedIn
                    }
                } catch {
                    print("❌ Error fetching profile: \(error)")
                    // Only sign out if it's a permission error
                    if let error = error as? UserServiceError, error == .permissionDenied {
                        try? Auth.auth().signOut()
                        DispatchQueue.main.async {
                            self.userService.currentUserProfile = nil // Clear the profile
                            self.authState = .signedOut
                        }
                    } else {
                        // For other errors, still consider the user signed in
                        DispatchQueue.main.async {
                            self.authState = .signedIn
                        }
                    }
                }
            }
        } else {
            print("👤 No user signed in")
            self.userService.currentUserProfile = nil // Clear the profile
            self.authState = .signedOut
        }
    }
}

// Wrapper to make String Identifiable for the .sheet modifier
struct IdentifiableString: Identifiable {
    let id: String
}

struct MainCoordinator: View {
    @StateObject var authViewModel: AuthViewModel = AuthViewModel()
    @State private var notificationPostIdWrapper: IdentifiableString? = nil
    
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var userService: UserService

    var body: some View {
        Group {
            switch authViewModel.authState {
            case .loading:
                LoadingView()
            case .signedOut:
                WelcomeView()
            case .signedIn:
                if let userId = Auth.auth().currentUser?.uid {
                    HomePage(userId: userId)
                } else {
                    Text("Error: No user ID available despite being signed in.")
                        .foregroundColor(.red)
                }
            case .emailVerificationRequired:
                EmailVerificationView()
            }
        }
        .sheet(item: $notificationPostIdWrapper) { wrapper in
            PostDetailViewWrapper(postId: wrapper.id)
                .environmentObject(postService)
                .environmentObject(userService)
                .environmentObject(authViewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .handlePushNotificationTap)) { notification in
            print("MainCoordinator received .handlePushNotificationTap via .onReceive: \\(notification.userInfo ?? [:])")
            if let postId = notification.userInfo?["postId"] as? String {
                print("Attempting to navigate to post detail for postId: \\(postId) via .onReceive")
                self.notificationPostIdWrapper = IdentifiableString(id: postId)
            }
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            Color(UIColor(red: 22/255, green: 23/255, blue: 26/255, alpha: 1.0))
                .ignoresSafeArea()
            
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
        }
    }
}

struct PostDetailViewWrapper: View {
    let postId: String
    @EnvironmentObject var postService: PostService
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var userService: UserService

    @State private var post: Post? = nil
    @State private var isLoading = true
    @State private var error: Error? = nil

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading post...")
            } else if let post = post {
                if let userId = authViewModel.authState == .signedIn ? Auth.auth().currentUser?.uid : nil {
                    NavigationView {
                        PostDetailView(post: post, userId: userId)
                    }
                } else {
                    Text("Error: User not authenticated to view post details.")
                }
            } else if let error = error {
                Text("Error loading post: \\(error.localizedDescription)")
            } else {
                Text("Post not found.")
            }
        }
        .onAppear {
            fetchPost()
        }
    }

    private func fetchPost() {
        isLoading = true
        Task {
            do {
                // Attempt to find in already loaded posts first
                if let existingPost = postService.posts.first(where: { $0.id == postId }) {
                    self.post = existingPost
                    self.isLoading = false
                    print("Post \\(postId) found in existing PostService.posts")
                    return
                }
                // If not found, fetch from Firestore
                print("Post \\(postId) not in PostService.posts, attempting fetch...")
                // This line assumes fetchSinglePost exists and is an async throws function in PostService
                self.post = try await postService.fetchSinglePost(byId: postId)
                self.isLoading = false
                if self.post == nil {
                    print("Post \\(postId) still not found after fetchSinglePost.")
                } else {
                    print("Post \\(postId) successfully fetched.")
                }
            } catch {
                self.error = error
                self.isLoading = false
                print("Error fetching post \\(postId): \\(error)")
            }
        }
    }
}

// Ensure LoadingView and other dependent views are defined or imported correctly.
// struct LoadingView: View { ... }
// struct WelcomeView: View { ... }
// struct HomePage: View { ... }
// struct EmailVerificationView: View { ... }
// struct PostDetailView: View { ... }
