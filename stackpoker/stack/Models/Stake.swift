import Foundation
import FirebaseFirestore

struct Stake: Codable, Identifiable {
    @DocumentID var id: String?
    let sessionId: String // ID of the Session object from Firestore
    let sessionGameName: String // To display on the dashboard easily
    let sessionStakes: String   // To display on the dashboard easily
    let sessionDate: Date       // To display on the dashboard easily

    let stakerUserId: String // For app users, or Stake.OFF_APP_STAKER_ID for manual stakers
    let stakedPlayerUserId: String

    let stakePercentage: Double // e.g., 0.10 for 10%
    let markup: Double            // e.g., 1.2 for 20% markup

    // Populated when the stake is created for a past, logged game
    var totalPlayerBuyInForSession: Double
    var playerCashoutForSession: Double
    
    // Settlement amount - stored field for database persistence
    var storedAmountTransferredAtSettlement: Double = 0
    
    // --- Revised Financial Logic for "After-the-Fact" Staking ---

    // 1. Player's net result for the entire session.
    var playerSessionNetResult: Double {
        return playerCashoutForSession - totalPlayerBuyInForSession
    }

    // 2. Staker's cost: their share of buy-in with markup applied
    var stakerCost: Double {
        return totalPlayerBuyInForSession * stakePercentage * markup
    }
    
    // 3. Staker's share of the cashout (no markup applied to winnings)
    var stakerShareOfCashout: Double {
        return playerCashoutForSession * stakePercentage
    }
    
    // 4. Amount transferred Player <> Staker at settlement. 
    //    Positive: Player pays Staker. Negative: Staker pays Player.
    //    This is what the staker receives minus what they paid.
    var amountTransferredAtSettlement: Double {
        // Always calculate fresh for now to ensure correct logic after recent fixes
        // TODO: Re-enable stored amount optimization after confirming all stored values are correct
        if totalPlayerBuyInForSession > 0 && playerCashoutForSession >= 0 {
            return stakerShareOfCashout - stakerCost
        }
        
        // Use stored amount only if we don't have session data to calculate from
        if storedAmountTransferredAtSettlement != 0 {
            return storedAmountTransferredAtSettlement
        }
        
        // Fallback to 0 for incomplete data
        return 0
    }

    // 5. Staker's overall net profit or loss from this stake.
    //    For "after-the-fact" staking with no upfront payment, this is simply amountTransferredAtSettlement.
    var stakerOverallNetProfitOrLoss: Double {
        return amountTransferredAtSettlement
    }
    
    // DEPRECATED: Keep for backward compatibility but no longer used
    var stakerShareOfPlayerNetResultBeforeMarkup: Double {
        return playerSessionNetResult * stakePercentage
    }
    
    // --- End of Revised Financial Logic ---

    // Fields for two-party settlement
    var settlementInitiatorUserId: String? = nil
    var settlementConfirmerUserId: String? = nil // To track who confirmed

    var status: StakeStatus
    let proposedAt: Date
    var acceptedAt: Date? // For this manual logging, can be same as proposedAt
    var declinedAt: Date?
    var settledAt: Date?
    var lastUpdatedAt: Date
    var isTournamentSession: Bool? // Added for differentiating stake type

    // New fields for off-app stakers
    var manualStakerDisplayName: String? = nil
    var isOffAppStake: Bool? = false
    
    // Field for tracking live session UUID (for immediately persisted stakes)
    var liveSessionId: String? = nil

    static let OFF_APP_STAKER_ID = "manual_off_app_staker_placeholder_id"

    enum StakeStatus: String, Codable {
        case pendingAcceptance = "pending_acceptance" // Might not be used for manually logged past games
        case active = "active"                        // Might not be used for manually logged past games
        case awaitingSettlement = "awaiting_settlement" // Initial state after session ends, before any settlement action
        case awaitingConfirmation = "awaiting_confirmation" // One party has marked settled, awaiting the other
        case settled = "settled"                      // Both parties agree, or one party finalized after a period
        case declined = "declined" // Might not be used
        case cancelled = "cancelled" // If the session log is deleted, associated stakes could be cancelled
    }

    // Firestore compatibility
    enum CodingKeys: String, CodingKey {
        case id
        case sessionId
        case sessionGameName
        case sessionStakes
        case sessionDate
        case stakerUserId
        case stakedPlayerUserId
        case stakePercentage
        case markup
        case totalPlayerBuyInForSession
        case playerCashoutForSession
        case storedAmountTransferredAtSettlement
        case settlementInitiatorUserId
        case settlementConfirmerUserId
        // Computed properties are not encoded/decoded directly
        case status
        case proposedAt
        case acceptedAt
        case declinedAt
        case settledAt
        case lastUpdatedAt
        case isTournamentSession
        case manualStakerDisplayName
        case isOffAppStake
        case liveSessionId
    }
    
    // Initializer for creating a new stake (e.g., from SessionFormView)
    init(
        id: String? = nil, // Allow passing ID for specific cases, though Firestore generates if nil
        sessionId: String,
        sessionGameName: String,
        sessionStakes: String,
        sessionDate: Date,
        stakerUserId: String,
        stakedPlayerUserId: String,
        stakePercentage: Double,
        markup: Double,
        totalPlayerBuyInForSession: Double,
        playerCashoutForSession: Double,
        storedAmountTransferredAtSettlement: Double = 0, // Default to 0, will be calculated
        status: StakeStatus = .awaitingSettlement, // Default for logged past games
        proposedAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        settlementInitiatorUserId: String? = nil, // Initializer param
        settlementConfirmerUserId: String? = nil,  // Initializer param
        isTournamentSession: Bool? = nil,         // Added to initializer
        manualStakerDisplayName: String? = nil,   // New initializer param
        isOffAppStake: Bool? = false,             // New initializer param
        liveSessionId: String? = nil              // New initializer param
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sessionGameName = sessionGameName
        self.sessionStakes = sessionStakes
        self.sessionDate = sessionDate
        self.stakerUserId = stakerUserId
        self.stakedPlayerUserId = stakedPlayerUserId
        self.stakePercentage = stakePercentage
        self.markup = markup
        self.totalPlayerBuyInForSession = totalPlayerBuyInForSession
        self.playerCashoutForSession = playerCashoutForSession
        self.storedAmountTransferredAtSettlement = storedAmountTransferredAtSettlement
        self.proposedAt = proposedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.settlementInitiatorUserId = settlementInitiatorUserId
        self.settlementConfirmerUserId = settlementConfirmerUserId
        self.isTournamentSession = isTournamentSession
        self.manualStakerDisplayName = manualStakerDisplayName
        self.isOffAppStake = isOffAppStake
        self.liveSessionId = liveSessionId

        // Manual stakers now follow the same settlement flow as app users
        self.status = status // Use the provided status or its default
        if status == .awaitingSettlement || status == .active || status == .awaitingConfirmation || status == .settled {
             self.acceptedAt = Date()
        } else {
             self.acceptedAt = nil
        }
        
        // Only set settledAt if the status is actually settled
        if status == .settled {
            self.settledAt = Date()
        }
    }
}

// Example Usage (for testing or understanding):
// Example 1 (Player Profit):
// let stakePlayerProfit = Stake(
//     sessionId: "session1", sessionGameName: "Game 1", sessionStakes: "$1/$2", sessionDate: Date(),
//     stakerUserId: "stakerA", stakedPlayerUserId: "playerB",
//     stakePercentage: 0.50, markup: 1.1,
//     totalPlayerBuyInForSession: 200, playerCashoutForSession: 300
// )
// print("--- Player Profit Scenario ---")
// print("Player Session Net Result: \(stakePlayerProfit.playerSessionNetResult)") // Expected: 100
// print("Staker Share Before Markup: \(stakePlayerProfit.stakerShareOfPlayerNetResultBeforeMarkup)") // Expected: 50
// print("Amount Player Pays Staker: \(stakePlayerProfit.amountTransferredAtSettlement)") // Expected: 55
// print("Staker Overall P/L: \(stakePlayerProfit.stakerOverallNetProfitOrLoss)") // Expected: 55

// Example 2 (Player Loss):
// let stakePlayerLoss = Stake(
//     sessionId: "session2", sessionGameName: "Game 2", sessionStakes: "$1/$2", sessionDate: Date(),
//     stakerUserId: "stakerA", stakedPlayerUserId: "playerB",
//     stakePercentage: 0.50, markup: 1.1,
//     totalPlayerBuyInForSession: 200, playerCashoutForSession: 100
// )
// print("\n--- Player Loss Scenario ---")
// print("Player Session Net Result: \(stakePlayerLoss.playerSessionNetResult)") // Expected: -100
// print("Staker Share Before Markup: \(stakePlayerLoss.stakerShareOfPlayerNetResultBeforeMarkup)") // Expected: -50
// print("Amount Player Pays Staker (Staker Pays Player): \(stakePlayerLoss.amountTransferredAtSettlement)") // Expected: -55
// print("Staker Overall P/L: \(stakePlayerLoss.stakerOverallNetProfitOrLoss)") // Expected: -55 


