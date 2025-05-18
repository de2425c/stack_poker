import SwiftUI
import FirebaseCore
import FirebaseAuth // Corrected typo and ensured it's present
import FirebaseMessaging // Keep this for push notifications
import UserNotifications // For UNUserNotificationCenterDelegate etc.

// Define a global Notification.Name for handling taps
extension Notification.Name {
    static let handlePushNotificationTap = Notification.Name("handlePushNotificationTap")
}

// AppDelegate to handle Firebase setup and Push Notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    let gcmMessageIDKey = "gcm.message_id"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        
        requestNotificationAuthorization(application: application)
        application.registerForRemoteNotifications()
        
        // Add this line to validate stored tokens
        validateStoredFCMToken()
        
        // Your existing UI setup code for TabBar and NavigationBar
        UITabBar.appearance().isHidden = true
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor.systemBlue
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
        UINavigationBar.appearance().tintColor            = .white
        DispatchQueue.main.async {
            if let tbc = UIApplication.shared
                .windows
                .first?
                .rootViewController as? UITabBarController,
               let vcs = tbc.viewControllers,
               vcs.count > 5 {
                tbc.viewControllers = Array(vcs.prefix(5))
                tbc.moreNavigationController.tabBarItem.isEnabled = false
            }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("Successfully registered for remote notifications with device token.")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let messageID = userInfo[gcmMessageIDKey] {
            print("Message ID: \(messageID)")
        }
        print("Received foreground notification: \(userInfo)")
        completionHandler([[.alert, .sound, .badge]])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        print("User tapped on notification. UserInfo: \(userInfo)")

        // Check if we have the postId and commentId for navigation
        if let postId = userInfo["postId"] as? String {
            var navigationData: [String: Any] = ["postId": postId]
            if let commentId = userInfo["commentId"] as? String {
                navigationData["commentId"] = commentId
            }
            
            print("Posting .handlePushNotificationTap with data: \(navigationData)")
            NotificationCenter.default.post(
                name: .handlePushNotificationTap, // Use the custom Notification.Name
                object: nil,
                userInfo: navigationData
            )
        } else {
            print("Notification tapped, but no postId found in userInfo for navigation.")
        }

        completionHandler()
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("Firebase registration token: \(String(describing: fcmToken))")
        
        // Create a token dictionary to post
        let dataDict: [String: String] = ["token": fcmToken ?? ""]
        
        // Post notification with token
        NotificationCenter.default.post(
            name: Notification.Name("FCMToken"),
            object: nil,
            userInfo: dataDict
        )
        
        guard let newToken = fcmToken, let userId = Auth.auth().currentUser?.uid else {
            print("FCM Token or User ID is nil, cannot process token update.")
            return
        }

        print("FCM Token received in AppDelegate: \(newToken) for user: \(userId).")

        // Retrieve the previous token *before* saving the new one as "LastFCMToken"
        let oldToken = UserDefaults.standard.string(forKey: "LastFCMToken")

        // Save the new token immediately to UserDefaults as the "LastFCMToken"
        UserDefaults.standard.set(newToken, forKey: "LastFCMToken")
        print("Saved new FCM token \(newToken) to UserDefaults as LastFCMToken.")

        Task {
            do {
                // Attempt to update/save the new token in Firestore
                // The stackApp observer will also attempt this, but this provides an earlier opportunity.
                // Consider if this direct call is duplicative or provides necessary immediacy.
                // For now, we keep it to ensure the new token is prioritized for saving.
                print("Attempting to save new token \(newToken) to Firestore via AppDelegate.")
                try await UserService().updateFCMToken(userId: userId, token: newToken)
                print("Successfully saved new token \(newToken) to Firestore via AppDelegate.")

                // Now, if there was an old token and it's different from the new one, invalidate it
                if let anOldToken = oldToken { // Safely unwrap oldToken
                    if !anOldToken.isEmpty && anOldToken != newToken { // Check if not empty AND different from new
                        print("Old FCM Token \(anOldToken) is different from new token \(newToken). Invalidating old token.")
                        await UserService().invalidateFCMToken(userId: userId, token: anOldToken)
                        print("Invalidation attempt for old token \(anOldToken) complete.")
                    } else if anOldToken.isEmpty {
                        print("Old token was found but it is empty. No invalidation needed.")
                    } else { // anOldToken == newToken
                        print("Old token is the same as the new token. No invalidation needed.")
                    }
                } else {
                    print("No old token found in UserDefaults.")
                }
            } catch {
                print("Error during FCM token update/invalidation process in AppDelegate: \(error.localizedDescription)")
            }
        }
    }
    
    private func requestNotificationAuthorization(application: UIApplication) {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in
                print("Permission granted for notifications: \(granted)")
                if let error = error {
                    print("Error requesting notification auth: \(error.localizedDescription)")
                }
                guard granted else { return }
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        )
    }

    // Add a helper method to check token validity on app startup
    private func validateStoredFCMToken() {
        // Only run if user is signed in
        guard let userId = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot validate FCM token: No user is signed in")
            return
        }
        
        // Check if we have a token stored
        if let storedToken = UserDefaults.standard.string(forKey: "LastFCMToken"),
           !storedToken.isEmpty {
            // If the current token from Messaging matches stored token, no action needed
            if let currentToken = Messaging.messaging().fcmToken, 
               currentToken == storedToken {
                print("✅ Stored FCM token is current")
            } else {
                // Either token has changed or we can't access current token yet
                print("🔄 Stored FCM token may need update, waiting for new token")
                // We'll let the didReceiveRegistrationToken callback handle this
            }
        } else {
            print("ℹ️ No FCM token stored yet")
        }
    }
}

@main
struct stackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject var userService = UserService()
    @StateObject var postService = PostService()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(.systemBackground)
                  .ignoresSafeArea()
                MainCoordinator()
                  .environmentObject(authViewModel)
                  .environmentObject(userService)
                  .environmentObject(postService)
                  .statusBar(hidden: true)
            }
            .onAppear {
                // Initial check if already signed in and profile is missing
                if authViewModel.authState == .signedIn && userService.currentUserProfile == nil {
                    Task {
                        do {
                            print("[stackApp.onAppear] User signed in, profile nil. Fetching profile.")
                            try await userService.fetchUserProfile()
                            print("[stackApp.onAppear] Profile fetch attempt complete.")
                        } catch {
                            print("[stackApp.onAppear] Error fetching user profile: \(error.localizedDescription)")
                        }
                    }
                }
                
                print("stackApp onAppear: Setting up FCMToken observer.") // For verifying observer setup
                NotificationCenter.default.addObserver(forName: Notification.Name("FCMToken" ), object: nil, queue: .main) { notification in
                    print("stackApp observer: Received FCMToken notification.") // For verifying notification received by observer
                    
                    let token = notification.userInfo?["token"] as? String
                    let currentAuthState = authViewModel.authState
                    let currentAuthUID = Auth.auth().currentUser?.uid

                    print("stackApp observer: Token: \(token ?? "nil"), AuthState: \(currentAuthState), AuthUID: \(currentAuthUID ?? "nil")")

                    if let token = token,
                       currentAuthState == .signedIn,
                       let userId = currentAuthUID {
                        Task {
                            do {
                                print("stackApp observer: Conditions met. Attempting to save FCM token: \(token) for user: \(userId)")
                                try await userService.updateFCMToken(userId: userId, token: token)
                                print("stackApp observer: FCM token successfully updated in Firestore.")
                            } catch {
                                print("stackApp observer: Error updating FCM token in Firestore: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        print("stackApp observer: Conditions NOT met for saving token.")
                        if token == nil {
                            print("stackApp observer: Reason - Token is nil.")
                        }
                        if currentAuthState != .signedIn {
                            print("stackApp observer: Reason - AuthState is NOT .signedIn (it is \(currentAuthState)).")
                        }
                        if currentAuthUID == nil {
                            print("stackApp observer: Reason - AuthUID is nil.")
                        }
                    }
                }
            }
        }
    }
}

struct InitialView: View { // Assuming this is where your MainCoordinator starts
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var userService: UserService

    var body: some View {
        // Your MainCoordinator or initial view structure
        MainCoordinator() // Example
            .onChange(of: authViewModel.authState) { newState in // Use older signature, no oldState
                print("[InitialView.onChange.authState] Auth state changed to \(newState).")
                if newState == .signedIn {
                    if userService.currentUserProfile == nil {
                        Task {
                            do {
                                print("[InitialView.onChange.authState] Auth state now .signedIn, profile nil. Fetching profile.")
                                try await userService.fetchUserProfile()
                                print("[InitialView.onChange.authState] Profile fetch attempt complete after auth state change.")
                            } catch {
                                print("[InitialView.onChange.authState] Error fetching user profile after auth state change: \(error.localizedDescription)")
                            }
                        }
                    } else {
                        print("[InitialView.onChange.authState] Auth state now .signedIn, profile was already loaded.")
                    }
                } else if newState == .signedOut {
                    // Clear user profile on sign out
                    DispatchQueue.main.async {
                        userService.currentUserProfile = nil
                        print("[InitialView.onChange.authState] Auth state now .signedOut. Cleared user profile.")
                    }
                }
            }
    }
}
