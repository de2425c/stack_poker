import SwiftUI
import FirebaseAuth

struct HandHistorySelectionView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var handStore: HandStore
    let onHandSelected: (String) -> Void
    
    @State private var searchText = ""
    
    var filteredHands: [SavedHand] {
        if searchText.isEmpty {
            return handStore.savedHands
        } else {
            return handStore.savedHands.filter { savedHand in
                // Search in player names, stakes, or final hand type
                let hand = savedHand.hand
                let players = hand.raw.players.map { $0.name.lowercased() }.joined(separator: " ")
                let stakes = "\(hand.raw.gameInfo.smallBlind)/\(hand.raw.gameInfo.bigBlind)"
                let finalHand = hand.raw.players.first(where: { $0.isHero })?.finalHand?.lowercased() ?? ""
                
                return players.contains(searchText.lowercased()) ||
                       stakes.contains(searchText.lowercased()) ||
                       finalHand.contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                
                VStack(spacing: 16) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                            .padding(.leading, 8)
                        
                        TextField("Search hands...", text: $searchText)
                            .foregroundColor(.white)
                            .padding(10)
                    }
                    .background(Color(UIColor(red: 40/255, green: 40/255, blue: 45/255, alpha: 1.0)))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    if handStore.savedHands.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                            
                            Text("No Hand Histories")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text("You don't have any saved hand histories to share")
                                .font(.system(size: 16))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        Spacer()
                    } else {
                        // Hand history list
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(filteredHands) { savedHand in
                                    HandSummaryRowSimple(savedHand: savedHand)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            onHandSelected(savedHand.id)
                                            presentationMode.wrappedValue.dismiss()
                                        }
                                        .padding(.horizontal)
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .navigationBarTitle("Select Hand History", displayMode: .inline)
                .navigationBarItems(
                    leading: Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .foregroundColor(.white)
                    }
                )
            }
        }
    }
}

struct HandSummaryRowSimple: View {
    let savedHand: SavedHand
    
    private func formatMoney(_ amount: Double) -> String {
        if amount >= 0 {
            return "$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }
    
    private var heroCards: [Card]? {
        if let hero = savedHand.hand.raw.players.first(where: { $0.isHero }),
           let cards = hero.cards {
            return cards.map { Card(from: $0) }
        }
        return nil
    }
    
    private var heroProfit: Double {
        return savedHand.hand.raw.pot.heroPnl
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Hand icon with profit indicator
            ZStack {
                Circle()
                    .fill(heroProfit >= 0 ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20))
                    .foregroundColor(heroProfit >= 0 ? .green : .red)
            }
            
            // Hand details
            VStack(alignment: .leading, spacing: 4) {
                // Show stake and date
                HStack {
                    Text("\(formatMoney(savedHand.hand.raw.gameInfo.smallBlind))/\(formatMoney(savedHand.hand.raw.gameInfo.bigBlind))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if let strength = savedHand.hand.raw.players.first(where: { $0.isHero })?.finalHand {
                        Text(strength)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                // Show hero cards if available
                if let cards = heroCards {
                    HStack(spacing: 4) {
                        ForEach(cards) { card in
                            Text("\(card.rank)\(card.suit)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 2)
                }
                
                // Profit/loss indicator
                Text(formatMoney(heroProfit))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(heroProfit >= 0 ? .green : .red)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.system(size: 14))
        }
        .padding(12)
        .background(Color(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 0.7)))
        .cornerRadius(10)
    }
} 

