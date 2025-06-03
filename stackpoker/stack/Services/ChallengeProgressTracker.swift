import Foundation
import Combine

@MainActor
class ChallengeProgressTracker: ObservableObject {
    private let challengeService: ChallengeService
    private let sessionStore: SessionStore
    private var cancellables = Set<AnyCancellable>()
    
    init(challengeService: ChallengeService, sessionStore: SessionStore) {
        self.challengeService = challengeService
        self.sessionStore = sessionStore
        setupTracking()
    }
    
    private func setupTracking() {
        // Track session updates to update bankroll challenges
        sessionStore.$sessions
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] sessions in
                Task {
                    await self?.updateBankrollChallenges(from: sessions)
                }
            }
            .store(in: &cancellables)
    }
    
    private func updateBankrollChallenges(from sessions: [Session]) async {
        // Update each active bankroll challenge individually using ONLY the sessions after the challenge start date
        for challenge in challengeService.activeChallenges where challenge.type == .bankroll {
            guard let challengeId = challenge.id else { continue }

            // Profit/loss only from sessions that started AFTER the challenge start date
            let profitSinceStart = sessions
                .filter { $0.startDate >= challenge.startDate }
                .reduce(0) { $0 + $1.profit }

            let startingBankroll = challenge.startingBankroll ?? 0
            let currentBankroll = startingBankroll + profitSinceStart

            // Only update if bankroll actually changed
            if abs(currentBankroll - challenge.currentValue) > 0.01 {
                do {
                    try await challengeService.updateChallengeProgress(
                        challengeId: challengeId,
                        newValue: currentBankroll,
                        triggerEvent: "session_update",
                        relatedEntityId: sessions.last?.id
                    )
                } catch {
                    print("❌ Error updating bankroll challenge: \(error)")
                }
            }
        }
    }
    
    // Method to manually trigger progress update (useful for one-time sync)
    func syncProgressForAllChallenges() async {
        await updateBankrollChallenges(from: sessionStore.sessions)
    }
} 