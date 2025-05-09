import SwiftUI
import FirebaseCore
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        UITabBar.appearance().isHidden = true

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

    init() {
        // Configure navigation bar appearance globally for white text
        let appearance = UINavigationBarAppearance()
        
        // Make it transparent with no shadow
        appearance.configureWithTransparentBackground()
        
        // Set white text for titles with increased weight
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]

        // Apply the appearance to all navigation bars
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        
        // Set white tint color for bar button items
        UINavigationBar.appearance().tintColor = .white
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ZStack {
                    // Background takes up full screen
                    AppBackgroundView()
                        .ignoresSafeArea()

                    // Main app content
                    MainCoordinator()
                        .environmentObject(authViewModel)
                        .statusBar(hidden: true)
                }
            }
            // Force white text/buttons
            .toolbarColorScheme(.dark, for: .navigationBar)
            .accentColor(.white)
        }
    }
}
