import SwiftUI
import FirebaseCore
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        UITabBar.appearance().isHidden = true
        let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()              // start from a blank, opaque canvas
                appearance.backgroundColor = UIColor.systemBlue         // ← your bar color
                appearance.titleTextAttributes = [
                    .foregroundColor: UIColor.white                    // inline title
                ]
                appearance.largeTitleTextAttributes = [
                    .foregroundColor: UIColor.white                    // large title
                ]
                // 2) Apply to all bar-states
                UINavigationBar.appearance().standardAppearance   = appearance
                UINavigationBar.appearance().scrollEdgeAppearance = appearance
                UINavigationBar.appearance().compactAppearance    = appearance
                // 3) Tint for back-chevron & any bar button items
                UINavigationBar.appearance().tintColor            = .white
        // Delay until the window is created on first run
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
}

@main
struct stackApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 1) fill the entire screen (including under the status bar)
                Color(.systemBackground)
                  .ignoresSafeArea()

                // 2) your existing coordinator
                MainCoordinator()
                  .environmentObject(authViewModel)
                  .statusBar(hidden: true)
            }
        }
    }
}
