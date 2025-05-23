import SwiftUI

struct FinishedSessionCardView: View {
    // Example session data - replace with your actual Session model/data
    let gameName: String
    let stakes: String
    let location: String
    let date: Date
    let duration: String // e.g., "3h 15m"
    let buyIn: Double
    let cashOut: Double
    let currencySymbol: String = "$" // Or determine dynamically
    
    // Customization Parameters
    var cardBackgroundColor: Color = Color(UIColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 1.0)) // Default dark
    var cardOpacity: Double = 1.0
    
    // Computed property for profit/loss
    var profit: Double {
        cashOut - buyIn
    }
    
    // Environment for detecting dark mode
    @Environment(\.colorScheme) var colorScheme

    // Determine text color based on card background and opacity for better readability
    private var effectiveTextColor: Color {
        // A simple heuristic: if card is very light or very transparent, use primary, else use white/gray
        // This might need more sophisticated logic for arbitrary colors.
        if cardOpacity < 0.5 || isColorLight(cardBackgroundColor) {
            return colorScheme == .dark ? .white : .primary // On very transparent, defer to system for contrast against actual background
        }
        return .white // Default for dark cards
    }
    
    private var effectiveSubTextColor: Color {
        if cardOpacity < 0.5 || isColorLight(cardBackgroundColor) {
            return .gray
        }
        return .gray // Standard gray for subtext usually works okay
    }
    
    // Helper to determine if a color is light (heuristic)
    private func isColorLight(_ color: Color) -> Bool {
        // This is a simplification. True color brightness calculation is more complex.
        // For SwiftUI Colors, direct component access isn't straightforward.
        // We might need to use UIColor for this if more precision is needed.
        // For now, let's assume named colors like .white, .yellow are light.
        // This won't work well for custom Color instances directly.
        // A more robust way would involve converting Color to UIColor.
        return color == .white || color == .yellow || color == Color(UIColor.systemGray5) || color == Color(UIColor.systemGray6)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            detailsView
            financialsView
            profitView
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackgroundColor)
                .opacity(cardOpacity)
        )
        .cornerRadius(12)
        .shadow(radius: 5)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(gameName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(effectiveTextColor)
                Text(stakes)
                    .font(.subheadline)
                    .foregroundColor(effectiveSubTextColor)
            }
            Spacer()
            Image("stack_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 30)
                .colorMultiply(effectiveTextColor) // Make logo color adapt
        }
    }

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(effectiveSubTextColor)
                Text(date, style: .date)
                    .foregroundColor(effectiveTextColor)
            }
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(effectiveSubTextColor)
                Text("Duration: \(duration)")
                    .foregroundColor(effectiveTextColor)
            }
        }
        .font(.callout)
    }
    
    private var financialsView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Buy In:")
                    .font(.subheadline)
                    .foregroundColor(effectiveSubTextColor)
                Spacer()
                Text("\(currencySymbol)\(buyIn, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundColor(effectiveTextColor)
            }
            
            HStack {
                Text("Cash Out:")
                    .font(.subheadline)
                    .foregroundColor(effectiveSubTextColor)
                Spacer()
                Text("\(currencySymbol)\(cashOut, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundColor(effectiveTextColor)
            }
            
            Divider()
                .background(effectiveSubTextColor.opacity(0.5))
        }
    }

    private var profitView: some View {
        HStack {
            Text("Profit/Loss:")
                .font(.headline)
                .foregroundColor(effectiveTextColor)
            Spacer()
            Text("\(profit >= 0 ? "+" : "")\(currencySymbol)\(profit, specifier: "%.2f")")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(profit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : Color.red)
        }
    }
}

// Enhanced preview provider
struct FinishedSessionCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Winning session preview
            FinishedSessionCardView(
                gameName: "NL Hold'em",
                stakes: "$1/$2",
                location: "Home Game",
                date: Date(),
                duration: "4h 30m",
                buyIn: 300.00,
                cashOut: 555.50
            )
            .previewLayout(.sizeThatFits)
            .padding()
            .previewDisplayName("Winning Session")
            
            // Losing session preview
            FinishedSessionCardView(
                gameName: "PLO",
                stakes: "$2/$5",
                location: "Bellagio",
                date: Date(),
                duration: "2h 45m",
                buyIn: 500.00,
                cashOut: 379.25
            )
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
            .padding()
            .previewDisplayName("Losing Session - Dark Mode")
        }
    }
} 
