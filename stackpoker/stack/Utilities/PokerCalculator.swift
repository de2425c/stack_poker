import Foundation

/// Utility class for poker calculations
class PokerCalculator {
    
    /// Calculate hero's profit or loss for a hand
    /// - Parameters:
    ///   - potAmount: Total pot amount
    ///   - heroContribution: How much hero contributed to the pot
    ///   - isWinner: Whether hero won the hand
    ///   - winningPlayers: Number of players who split the pot (if hero is among winners)
    /// - Returns: Hero's profit/loss amount (positive for profit, negative for loss)
    static func calculateHeroPnL(potAmount: Double, heroContribution: Double, isWinner: Bool, winningPlayers: Int = 1) -> Double {
        // If hero lost, PnL is negative their contribution
        if !isWinner {
            return -heroContribution
        }
        
        // If hero won and pot is split
        if winningPlayers > 1 {
            let heroShare = potAmount / Double(winningPlayers)
            return heroShare - heroContribution
        }
        
        // Hero won the entire pot
        return potAmount - heroContribution
    }
    
    /// Calculate hero's PnL based on a ParsedHandHistory
    /// - Parameter hand: The hand history to analyze
    /// - Returns: Hero's profit/loss amount
    static func calculateHandHistoryPnL(hand: RawHandHistory) -> Double {
        // Get hero player
        guard let hero = hand.players.first(where: { $0.isHero }) else {
            return 0
        }
        
        // Track the total hero's contribution
        var totalHeroContribution: Double = 0
        
        // Track hero's contribution per street (needed for proper calculation)
        var streetInvestments: [String: Double] = [:]
        
        // Process each street and update the total contribution properly
        for street in hand.streets {
            var currentStreetContribution: Double = 0
            
            // Calculate highest bet on the street (for proper call amount calculation)
            var highestBetOnStreet: Double = 0
            
            // First pass: find the highest bet on this street
            for action in street.actions {
                if action.action.lowercased() == "bets" || action.action.lowercased() == "raises" {
                    highestBetOnStreet = max(highestBetOnStreet, action.amount)
                }
            }
            
            // Second pass: process hero's actions
            for action in street.actions {
                if action.playerName == hero.name {
                    let actionType = action.action.lowercased()
                    
                    switch actionType {
                    case "posts small blind", "posts big blind", "posts":
                        // Blinds and antes are simple - just add the amount
                        currentStreetContribution += action.amount
                        
                    case "bets":
                        // For a bet, the full amount is added
                        currentStreetContribution += action.amount
                        
                    case "raises":
                        // For a raise, it's the difference between the raise amount and what hero has already invested
                        let additionalAmount = action.amount - currentStreetContribution
                        currentStreetContribution = action.amount  // Now hero has this much invested on the street
                        
                    case "calls":
                        // For a call, it's the difference between the call amount and what hero already put in
                        let additionalAmount = highestBetOnStreet - currentStreetContribution
                        if additionalAmount > 0 {
                            currentStreetContribution += additionalAmount
                        }
                        
                    case "folds":
                        // No additional money added when folding
                        break
                        
                    case "checks":
                        // No money added for checks
                        break
                        
                    default:
                        break
                    }
                }
                // Update highest bet for call calculations
                else if action.action.lowercased() == "bets" || action.action.lowercased() == "raises" {
                    highestBetOnStreet = max(highestBetOnStreet, action.amount)
                }
            }
            
            // Add this street's contribution to the total
            totalHeroContribution += currentStreetContribution
            streetInvestments[street.name] = currentStreetContribution
        }
        
        // Check if hero is a winner
        let isWinner: Bool
        var winnerCount = 1
        
        if let distribution = hand.pot.distribution, !distribution.isEmpty {
            // Use pot distribution to determine if hero won
            let winningPlayers = distribution.filter { $0.amount > 0 }.map { $0.playerName }
            isWinner = winningPlayers.contains(hero.name)
            winnerCount = winningPlayers.count
        } else {
            // Check if hero folded
            let heroFolded = hand.streets.flatMap { $0.actions }.contains { 
                $0.playerName == hero.name && $0.action.lowercased() == "folds"
            }
            
            if heroFolded {
                return -totalHeroContribution
            }
            
            // Count active (non-folded) players at the end
            let allFolded = Set(hand.streets.flatMap { $0.actions }
                .filter { $0.action.lowercased() == "folds" }
                .map { $0.playerName })
            
            let activePlayers = hand.players.filter { !allFolded.contains($0.name) }
            
            // If hero is the only player left, they won
            if activePlayers.count == 1 && activePlayers.first?.isHero == true {
                return hand.pot.amount - totalHeroContribution
            }
            
            // If we can't determine definitively, use the game's final actions to infer
            let lastStreet = hand.streets.last
            let lastAction = lastStreet?.actions.last
            
            // If the last action was hero calling and there's a showdown, check the pot size
            if lastAction?.playerName == hero.name && lastAction?.action.lowercased() == "calls" {
                // Hero called on the last action, so they probably lost at showdown
                return -totalHeroContribution
            }
            
            // If we get here and can't determine, fall back to the recorded value
            return hand.pot.heroPnl
        }
        
        return calculateHeroPnL(
            potAmount: hand.pot.amount,
            heroContribution: totalHeroContribution,
            isWinner: isWinner,
            winningPlayers: winnerCount
        )
    }
} 