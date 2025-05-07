import SwiftUI

enum AuthScreen {
    case splash
    case welcome
    case signIn
}

class AuthNavigationState: ObservableObject {
    @Published var currentScreen: AuthScreen = .splash
} 