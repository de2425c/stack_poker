import SwiftUI

struct HandsListView: View {
    @ObservedObject var handStore: HandStore
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(handStore.savedHands) { savedHand in
                    HandSummaryRow(hand: savedHand.hand)
                        .background(Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)))
                        .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

// ... existing code ... 