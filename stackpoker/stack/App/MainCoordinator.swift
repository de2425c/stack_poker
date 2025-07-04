import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Combine

@MainActor
class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading // <— legacy
    @Published var appFlow: AppFlow = .loading      // ✅ single source of truth
    @Published var userService: UserService
    @State private var isRefreshingFlow = false // Debounce flag
    
    enum AuthState {
        case loading
        case signedOut
        case signedIn
        case emailVerificationRequired
    }
    
    // MARK: - Auth state listener
    /// Firebase auth state change listener handle. We keep a strong reference so we can detach on deinit.
    private var authListenerHandle: AuthStateDidChangeListenerHandle?

    // Track when the auth state was last updated for debugging
    private var lastAuthStateUpdate = Date()
    
    // Set auth state with tracking
    private func setAuthState(_ newState: AuthState) {
        let previousState = self.authState
        self.authState = newState
        
        // Track timing and log state transitions
        let now = Date()
        let timeSinceLastUpdate = now.timeIntervalSince(lastAuthStateUpdate)
        lastAuthStateUpdate = now
        

    }

    /// Adds a Firebase `AuthStateDidChangeListener` so the view model reacts instantly to log-in / log-out events
    /// coming from any part of the app. This removes the need to manually call `checkAuthState()` after every
    /// authentication operation and guarantees the UI always reflects the most up-to-date auth state.
    private func addAuthStateListener() {
        if let handle = authListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        authListenerHandle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            guard let self = self else { return }
            Task { self.refreshFlow() }
        }
    }

    /// Central helper that converts a Firebase `User?` into our `AuthState` and performs any additional
    /// housekeeping such as loading / clearing the profile.
    private func processFirebaseUser(_ user: FirebaseAuth.User?) {
        if let user = user {


            // Get latest user verification status
            Task {
                do {
                    // CRITICAL FIX: Force reload the user to get the latest verification status
                    try await user.reload()
                    
                    // Get the fresh user object after reload
                    guard let freshUser = Auth.auth().currentUser else {

                        self.userService.currentUserProfile = nil
                        self.setAuthState(.signedOut)
                        return
                    }
                    
                    // Email verification check with the latest status
                    if !freshUser.isEmailVerified {

                        self.setAuthState(.emailVerificationRequired)
                        return
                    }
                    

                    try await self.userService.fetchUserProfile()
                    
                    self.setAuthState(.signedIn)

                } catch {

                    
                    // Handle specific errors
                    if let serviceError = error as? UserServiceError, serviceError == .permissionDenied {
                        // Profile access issue - sign out
                        try? Auth.auth().signOut()
                        self.userService.currentUserProfile = nil
                        self.setAuthState(.signedOut)
                    } else if let serviceError = error as? UserServiceError, serviceError == .profileNotFound {
                        // Profile not created yet but email might be verified
                        if let currentUser = Auth.auth().currentUser, currentUser.isEmailVerified {
                            self.setAuthState(.signedIn)

                        } else {
                            self.setAuthState(.emailVerificationRequired)
                        }
                    } else {
                        // General error - default to signed in state
                        self.setAuthState(.signedIn)

                    }
                }
            }
        } else {

            self.userService.currentUserProfile = nil
            self.setAuthState(.signedOut)
        }
    }

    // MARK: - Initialisation
    init() {
        self.userService = UserService()
        // Set up listener first so we instantly react to auth changes
        addAuthStateListener()
        refreshFlow()
    }

    deinit {
        if let handle = authListenerHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Existing methods
    /// Explicit check that can still be called manually – it now just delegates to the new helper.
    func checkAuthState() { refreshFlow() }
    
    // Verify that the current user ID matches the stored profile ID to prevent profile mismatch
    func verifyProfileConsistency() {
        // No longer need DispatchQueue.main.async as class is @MainActor
        // If we have a signed-in user but the profile is for a different user, clear it
        if let currentUser = Auth.auth().currentUser,
           let profile = self.userService.currentUserProfile,
           currentUser.uid != profile.id {

            // Clear the profile to force a refresh
            self.userService.clearUserData() // This is @MainActor
            // Fetch the correct profile
            Task {
                // userService.fetchUserProfile is @MainActor, called from a Task
                try? await self.userService.fetchUserProfile()
            }
        }
    }

    // Use this method for explicit sign out to ensure proper cleanup
    func signOut() {
        do {
            // First post notification to let services clear their data
            NotificationCenter.default.post(name: NSNotification.Name("UserWillSignOut"), object: nil)
            
            // Then sign out from Firebase
            try Auth.auth().signOut()
            
            // The auth state listener will handle UI updates

        } catch {

        }
    }

    // Helper method to force a specific auth state (for debugging)
    func forceAuthState(_ state: AuthState) {

        setAuthState(state)
    }

    // MARK: - Single refresh point
    func refreshFlow() {
        guard !isRefreshingFlow else {
            print("AuthViewModel: Already refreshing flow, skipping")
            return
        }
        isRefreshingFlow = true
        print("AuthViewModel: Starting flow refresh")
        // Ensure the flag is reset when the function exits, however it exits.
        defer { 
            isRefreshingFlow = false 
            print("AuthViewModel: Flow refresh completed")
        }


        setAppFlow(.loading)

        guard let firebaseUser = Auth.auth().currentUser else {

            setAppFlow(.signedOut)
            return
        }

        Task {
            do {

                try await firebaseUser.reload()

                // Check if user is authenticated via phone number
                let isPhoneUser = firebaseUser.providerData.contains { provider in
                    provider.providerID == "phone"
                }
                
                // For phone users, skip email verification
                let verified = isPhoneUser ? true : firebaseUser.isEmailVerified

                // Does profile exist?
                var profileExists = false
                if self.userService.currentUserProfile != nil {

                    profileExists = true
                } else {

                    let doc = try await Firestore.firestore()
                        .collection("users").document(firebaseUser.uid).getDocument()
                    profileExists = doc.exists

                }

                print("AuthViewModel: User is phone user: \(isPhoneUser), Email verified: \(firebaseUser.isEmailVerified), Considered verified: \(verified), Profile exists: \(profileExists)")

                if !verified {
                    print("AuthViewModel: Setting flow to emailVerification")
                    setAppFlow(.emailVerification)
                } else if !profileExists {
                    print("AuthViewModel: Setting flow to profileSetup")
                    setAppFlow(.profileSetup)
                } else {
                    print("AuthViewModel: User verified and profile exists - setting to main flow")
                    // cache profile
                    if self.userService.currentUserProfile == nil {
                        print("AuthViewModel: Fetching user profile...")
                        try await userService.fetchUserProfile()
                        print("AuthViewModel: User profile fetched")
                    }
                    print("AuthViewModel: Setting app flow to main(userId: \(firebaseUser.uid))")
                    setAppFlow(.main(userId: firebaseUser.uid))
                    print("AuthViewModel: App flow set to main successfully")
                }
            } catch {

                setAppFlow(.signedOut)
            }
        }
    }

    // Helper to update flow with logging
    private func setAppFlow(_ newFlow: AppFlow) {
        print("AuthViewModel: setAppFlow called with: \(newFlow)")
        print("AuthViewModel: Current app flow: \(self.appFlow)")
        
        if newFlow == self.appFlow { 
            print("AuthViewModel: New flow same as current, skipping")
            return 
        }

        print("AuthViewModel: Updating app flow from \(self.appFlow) to \(newFlow)")
        self.appFlow = newFlow
        print("AuthViewModel: App flow updated successfully to: \(self.appFlow)")
    }

    // MARK: - Public helper to force main flow after onboarding
    @MainActor
    func enterMainFlow() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        isRefreshingFlow = false // reset debounce flag
        setAppFlow(.main(userId: uid))
    }
    
    // MARK: - Public method to force app flow directly (for profile setup completion)
    @MainActor
    func forceAppFlow(_ newFlow: AppFlow) {
        print("AuthViewModel: Forcing app flow to: \(newFlow)")
        isRefreshingFlow = false // reset debounce flag
        setAppFlow(newFlow)
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
        NavigationStack {
            switch authViewModel.appFlow {
            case .loading:
                LoadingView()
                    .onAppear { print("MainCoordinator: Showing LoadingView") }
            case .signedOut:
                WelcomeView()
                    .onAppear { print("MainCoordinator: Showing WelcomeView") }
            case .emailVerification:
                EmailVerificationView()
                    .onAppear { print("MainCoordinator: Showing EmailVerificationView") }
            case .profileSetup:
                ProfileSetupView(isNewUser: true)
                    .environmentObject(authViewModel)
                    .environmentObject(userService)
                    .onAppear { print("MainCoordinator: Showing ProfileSetupView") }
            case .main(let userId):
                HomePage(userId: userId)
                    .onAppear { print("MainCoordinator: Showing HomePage for user: \(userId)") }
            }
        }
        .onChange(of: authViewModel.appFlow) { newFlow in
            print("MainCoordinator: App flow changed to: \(newFlow)")
        }
        .sheet(item: $notificationPostIdWrapper) { wrapper in
            PostDetailViewWrapper(postId: wrapper.id)
                .environmentObject(postService)
                .environmentObject(userService)
                .environmentObject(authViewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .handlePushNotificationTap)) { notification in

            if let postId = notification.userInfo?["postId"] as? String {

                self.notificationPostIdWrapper = IdentifiableString(id: postId)
            }
        }
        .onAppear {
            // Verify profile consistency on app startup
            authViewModel.verifyProfileConsistency()
        }
    }
}

struct LoadingView: View {
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                Text("Loading...")
                    .font(.custom("PlusJakartaSans-Medium", size: 16))
                    .foregroundColor(.white.opacity(0.8))
            }
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

                    return
                }
                // If not found, fetch from Firestore

                // This line assumes fetchSinglePost exists and is an async throws function in PostService
                self.post = try await postService.fetchSinglePost(byId: postId)
                self.isLoading = false
                if self.post == nil {

                } else {

                }
            } catch {
                self.error = error
                self.isLoading = false

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
