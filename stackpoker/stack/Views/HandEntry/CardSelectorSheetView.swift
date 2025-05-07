import SwiftUI

struct CardSelectorSheetView: View {
    @Binding var selectedCard: String?
    let usedCards: Set<String>
    let title: String
    @Environment(\.dismiss) var dismissSheet
    
    private let viewModel = HandEntryViewModel() // For constants
    
    var body: some View {
        // Removed outer NavigationView, doesn't work well in popover
        VStack(spacing: 0) { 
            // Header
            Text("Select \(title) Card")
                .font(.headline)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial) // Use material for header
            
            Divider()
            
            // Grid View
            CardSelectorView(
                title: "", // Title handled by header
                selectedCard: $selectedCard,
                usedCards: usedCards, 
                ranks: viewModel.cardRanks, 
                suits: viewModel.cardSuits
            )
            .padding() 

            Spacer() // Push button down
            
            // Done Button
            Button("Done") { dismissSheet() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 123/255, green: 255/255, blue: 99/255)) // App accent
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial) // Background for button area
        }
        // Apply AppBackgroundView to the main VStack of the sheet content
        .background(AppBackgroundView().ignoresSafeArea())
        .interactiveDismissDisabled(false) 
        // Suggesting ideal height for popover mode
        .frame(idealHeight: 450)
         // presentationDetents are less relevant for popover
    }
} 