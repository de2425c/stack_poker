import Foundation
import FirebaseFirestore

struct EventStakingInvite: Codable, Identifiable {
    @DocumentID var id: String?
    let eventId: String // Reference to the public event
    let eventName: String
    let eventDate: Date
    let stakedPlayerUserId: String // The player who set up the staking
    let stakerUserId: String // The invited staker (or manual staker ID)
    
    // Global staking details
    let maxBullets: Int
    let markup: Double
    
    // Individual staker details
    let percentageBought: Double // How much % they bought
    let amountBought: Double // Dollar amount they bought
    
    // Manual staker info (if applicable)
    let isManualStaker: Bool
    let manualStakerDisplayName: String?
    
    // Session results (populated when session is completed)
    var sessionBuyIn: Double?
    var sessionCashout: Double?
    var sessionCompletedAt: Date?
    
    // Status and timestamps
    var status: InviteStatus
    let createdAt: Date
    var respondedAt: Date?
    var lastUpdatedAt: Date
    
    enum InviteStatus: String, Codable, CaseIterable {
        case pending = "pending"
        case accepted = "accepted"
        case declined = "declined"
        case expired = "expired"
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventId
        case eventName
        case eventDate
        case stakedPlayerUserId
        case stakerUserId
        case maxBullets
        case markup
        case percentageBought
        case amountBought
        case isManualStaker
        case manualStakerDisplayName
        case sessionBuyIn
        case sessionCashout
        case sessionCompletedAt
        case status
        case createdAt
        case respondedAt
        case lastUpdatedAt
    }
    
    init(
        id: String? = nil,
        eventId: String,
        eventName: String,
        eventDate: Date,
        stakedPlayerUserId: String,
        stakerUserId: String,
        maxBullets: Int,
        markup: Double,
        percentageBought: Double,
        amountBought: Double,
        isManualStaker: Bool = false,
        manualStakerDisplayName: String? = nil,
        sessionBuyIn: Double? = nil,
        sessionCashout: Double? = nil,
        sessionCompletedAt: Date? = nil,
        status: InviteStatus = .pending,
        createdAt: Date = Date(),
        respondedAt: Date? = nil,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.eventId = eventId
        self.eventName = eventName
        self.eventDate = eventDate
        self.stakedPlayerUserId = stakedPlayerUserId
        self.stakerUserId = stakerUserId
        self.maxBullets = maxBullets
        self.markup = markup
        self.percentageBought = percentageBought
        self.amountBought = amountBought
        self.isManualStaker = isManualStaker
        self.manualStakerDisplayName = manualStakerDisplayName
        self.sessionBuyIn = sessionBuyIn
        self.sessionCashout = sessionCashout
        self.sessionCompletedAt = sessionCompletedAt
        self.status = status
        self.createdAt = createdAt
        self.respondedAt = respondedAt
        self.lastUpdatedAt = lastUpdatedAt
    }
    
    // Computed properties
    var hasSessionResults: Bool {
        return sessionBuyIn != nil && sessionCashout != nil && sessionCompletedAt != nil
    }
    
    var sessionProfit: Double? {
        guard let buyIn = sessionBuyIn, let cashout = sessionCashout else { return nil }
        return cashout - buyIn
    }
}

extension EventStakingInvite.InviteStatus {
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .expired: return "Expired"
        }
    }
    
    var icon: String {
        switch self {
        case .pending: return "clock"
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .expired: return "exclamationmark.triangle.fill"
        }
    }
} 