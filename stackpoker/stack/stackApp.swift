import SwiftUI
import FirebaseCore
import FirebaseAuth // Corrected typo and ensured it's present
import FirebaseMessaging // Keep this for push notifications
import FirebaseCrashlytics // Crash reporting
import UserNotifications // For UNUserNotificationCenterDelegate etc.

// Define a global Notification.Name for handling taps
extension Notification.Name {
    static let handlePushNotificationTap = Notification.Name("handlePushNotificationTap")
}

// Register fonts
struct FontRegistration {
    static func register() {
        // Register Plus Jakarta Sans fonts
        registerFont(bundle: .main, fontName: "PlusJakartaSans-Regular", fontExtension: "ttf")
        registerFont(bundle: .main, fontName: "PlusJakartaSans-Medium", fontExtension: "ttf")
        registerFont(bundle: .main, fontName: "PlusJakartaSans-SemiBold", fontExtension: "ttf")
        registerFont(bundle: .main, fontName: "PlusJakartaSans-Bold", fontExtension: "ttf")
    }
    
    private static func registerFont(bundle: Bundle, fontName: String, fontExtension: String) {
        guard let fontURL = bundle.url(forResource: fontName, withExtension: fontExtension),
              let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
              let font = CGFont(fontDataProvider) else {

            return
        }
        
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterGraphicsFont(font, &error) {

        }
    }
}

// AppDelegate to handle Firebase setup and Push Notifications
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    
    let gcmMessageIDKey = "gcm.message_id"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
        // Configure Firebase Auth for phone verification immediately after configure
        configureFirebaseAuth()
        
        // Register custom fonts
        FontRegistration.register()
        
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
        appearance.backgroundColor = UIColor(white: 0.1, alpha: 0.01) // Almost clear but technically opaque
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.shadowColor = .clear // Remove the shadow line
        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
        UINavigationBar.appearance().tintColor 
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
        
        // Set APNs token for Firebase Auth (required for phone verification)
        #if DEBUG
        Auth.auth().setAPNSToken(deviceToken, type: .sandbox)
        #else
        Auth.auth().setAPNSToken(deviceToken, type: .prod)
        #endif
        
        print("AppDelegate: APNs token set for Firebase Auth")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("AppDelegate: Failed to register for push notifications with error: \(error)")
    }
    
    // Handle incoming notification while app is active (required for phone auth)
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Pass notification to Firebase Auth for phone verification
        if Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        
        // Handle other notifications
        completionHandler(.newData)
    }
    
    // Handle URL schemes for Firebase Auth (required for phone verification)
    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        // Check if Firebase Auth can handle this URL
        if Auth.auth().canHandle(url) {
            print("AppDelegate: Firebase Auth handled URL: \(url)")
            return true
        }
        
        // URL not auth related; handle separately if needed
        print("AppDelegate: URL not handled by Firebase Auth: \(url)")
        return false
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        if let messageID = userInfo[gcmMessageIDKey] {

        }

        completionHandler([[.alert, .sound, .badge]])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        


        // Check if we have the postId and commentId for navigation
        if let postId = userInfo["postId"] as? String {
            var navigationData: [String: Any] = ["postId": postId]
            if let commentId = userInfo["commentId"] as? String {
                navigationData["commentId"] = commentId
            }
            

            NotificationCenter.default.post(
                name: .handlePushNotificationTap, // Use the custom Notification.Name
                object: nil,
                userInfo: navigationData
            )
        } else {

        }

        completionHandler()
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {

        
        // Create a token dictionary to post
        let dataDict: [String: String] = ["token": fcmToken ?? ""]
        
        // Post notification with token
        NotificationCenter.default.post(
            name: Notification.Name("FCMToken"),
            object: nil,
            userInfo: dataDict
        )
        
        guard let newToken = fcmToken, let userId = Auth.auth().currentUser?.uid else {

            return
        }



        // Retrieve the previous token *before* saving the new one as "LastFCMToken"
        let oldToken = UserDefaults.standard.string(forKey: "LastFCMToken")

        // Save the new token immediately to UserDefaults as the "LastFCMToken"
        UserDefaults.standard.set(newToken, forKey: "LastFCMToken")


        Task {
            do {
                // Attempt to update/save the new token in Firestore
                // The stackApp observer will also attempt this, but this provides an earlier opportunity.
                // Consider if this direct call is duplicative or provides necessary immediacy.
                // For now, we keep it to ensure the new token is prioritized for saving.

                try await UserService().updateFCMToken(userId: userId, token: newToken)


                // Now, if there was an old token and it's different from the new one, invalidate it
                if let anOldToken = oldToken { // Safely unwrap oldToken
                    if !anOldToken.isEmpty && anOldToken != newToken { // Check if not empty AND different from new

                        await UserService().invalidateFCMToken(userId: userId, token: anOldToken)

                    } else if anOldToken.isEmpty {

                    } else { // anOldToken == newToken

                    }
                } else {

                }
            } catch {

            }
        }
    }
    
    private func requestNotificationAuthorization(application: UIApplication) {
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(
            options: authOptions,
            completionHandler: { granted, error in

                if let error = error {

                }
                guard granted else { return }
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications()
                }
            }
        )
    }

    // Configure Firebase Auth settings for phone verification
    private func configureFirebaseAuth() {
        #if DEBUG
        Auth.auth().settings?.isAppVerificationDisabledForTesting = true
        print("AppDelegate: Testing mode enabled - use fictional phone numbers")
        #endif
        
        // Set language code for better compatibility
        Auth.auth().languageCode = "en"
        
        print("AppDelegate: Firebase Auth configured for phone verification")
    }
    
    // Add a helper method to check token validity on app startup
    private func validateStoredFCMToken() {
        // Only run if user is signed in
        guard let userId = Auth.auth().currentUser?.uid else {

            return
        }
        
        // Check if we have a token stored
        if let storedToken = UserDefaults.standard.string(forKey: "LastFCMToken"),
           !storedToken.isEmpty {
            // If the current token from Messaging matches stored token, no action needed
            if let currentToken = Messaging.messaging().fcmToken, 
               currentToken == storedToken {

            } else {
                // Either token has changed or we can't access current token yet

                // We'll let the didReceiveRegistrationToken callback handle this
            }
        } else {

        }
    }
}

@main
struct stackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject var userService = UserService()
    @StateObject var postService = PostService()
    @State private var showInitialLottie = true
    @State private var playInitialLottie = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppBackgroundView().ignoresSafeArea()
                
                if showInitialLottie {
                    // Always show Lottie first to prevent white screen
                    LottieView(name: "lottie_final", loopMode: .loop, play: $playInitialLottie)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            playInitialLottie = true
                        }
                } else {
                    MainCoordinator()
                      .environmentObject(authViewModel)
                      .environmentObject(userService)
                      .environmentObject(postService)
                }
            }
            .autocorrectionDisabled(true)     
            .textInputAutocapitalization(.never)
            .onChange(of: authViewModel.appFlow) { newFlow in
                // Hide the initial Lottie once the app has determined its flow
                if newFlow != .loading {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showInitialLottie = false
                    }
                }
            }
            .onAppear {
                // Give a minimum time for the Lottie to show, then check auth state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if authViewModel.appFlow != .loading {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showInitialLottie = false
                        }
                    }
                }
                
                // Initial check if already signed in and profile is missing
                if authViewModel.authState == .signedIn && userService.currentUserProfile == nil {
                    Task {
                        do {

                            try await userService.fetchUserProfile()

                        } catch {

                        }
                    }
                }
                
                print("stackApp onAppear: Setting up FCMToken observer.") // For verifying observer setup
                NotificationCenter.default.addObserver(forName: Notification.Name("FCMToken" ), object: nil, queue: .main) { notification in
                    print("stackApp observer: Received FCMToken notification.") // For verifying notification received by observer
                    
                    let token = notification.userInfo?["token"] as? String
                    let currentAuthState = authViewModel.authState
                    let currentAuthUID = Auth.auth().currentUser?.uid



                    if let token = token,
                       currentAuthState == .signedIn,
                       let userId = currentAuthUID {
                        Task {
                            do {

                                try await userService.updateFCMToken(userId: userId, token: token)

                            } catch {

                            }
                        }
                    } else {

                        if token == nil {

                        }
                        if currentAuthState != .signedIn {

                        }
                        if currentAuthUID == nil {

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

                if newState == .signedIn {
                    if userService.currentUserProfile == nil {
                        Task {
                            do {

                                try await userService.fetchUserProfile()

                            } catch {

                            }
                        }
                    } else {

                    }
                } else if newState == .signedOut {
                    // Clear user profile on sign out
                    DispatchQueue.main.async {
                        userService.currentUserProfile = nil

                    }
                }
            }
    }
}
