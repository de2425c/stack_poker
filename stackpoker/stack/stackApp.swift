//
//  stackApp.swift
//  stack
//
//  Created by David Eyal on 4/25/25.
//

import SwiftUI
import FirebaseCore
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        
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
            MainCoordinator()
                .environmentObject(authViewModel)
        }
    }
}
