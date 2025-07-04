import SwiftUI
import Combine

// MARK: - Live Session Coordinator

class LiveSessionCoordinator: ObservableObject, LiveSessionSetupDelegate {
    let userId: String
    let sessionStore: SessionStore
    let onDismiss: () -> Void
    
    @Published var currentView: CoordinatorViewState = .setup
    @Published var sessionConfiguration: SessionConfiguration?
    @Published var preselectedEvent: Event?
    
    enum CoordinatorViewState {
        case setup
        case activeSession
    }
    
    init(userId: String, sessionStore: SessionStore, onDismiss: @escaping () -> Void, preselectedEvent: Event? = nil) {
        self.userId = userId
        self.sessionStore = sessionStore
        self.onDismiss = onDismiss
        self.preselectedEvent = preselectedEvent
    }
    
    // MARK: - LiveSessionSetupDelegate
    
    func didCompleteSetup(with configuration: SessionConfiguration) {
        self.sessionConfiguration = configuration
        self.currentView = .activeSession
    }
    
    func didCancelSetup() {
        onDismiss()
    }
    
    // MARK: - Session Management
    
    func didEndSession() {
        onDismiss()
    }
    
    func backToSetup() {
        self.currentView = .setup
        self.sessionConfiguration = nil
    }
}

// MARK: - Coordinator View

struct LiveSessionCoordinatorView: View {
    @StateObject private var coordinator: LiveSessionCoordinator
    
    init(userId: String, sessionStore: SessionStore, onDismiss: @escaping () -> Void, preselectedEvent: Event? = nil) {
        self._coordinator = StateObject(wrappedValue: LiveSessionCoordinator(
            userId: userId,
            sessionStore: sessionStore,
            onDismiss: onDismiss,
            preselectedEvent: preselectedEvent
        ))
    }
    
    var body: some View {
        Group {
            switch coordinator.currentView {
            case .setup:
                LiveSessionSetupView(
                    userId: coordinator.userId,
                    preselectedEvent: coordinator.preselectedEvent,
                    delegate: coordinator
                )
                
            case .activeSession:
                if let configuration = coordinator.sessionConfiguration {
                    EnhancedLiveSessionView(
                        userId: coordinator.userId,
                        sessionStore: coordinator.sessionStore,
                        sessionConfiguration: configuration,
                        onSessionEnd: coordinator.didEndSession
                    )
                } else {
                    // Fallback - should not happen
                    LiveSessionSetupView(
                        userId: coordinator.userId,
                        preselectedEvent: coordinator.preselectedEvent,
                        delegate: coordinator
                    )
                }
            }
        }
    }
} 