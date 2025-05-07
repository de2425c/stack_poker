import SwiftUI

// MARK: - Formatters

func currencyFormatter(maxFractionDigits: Int = 0) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = maxFractionDigits
    formatter.minimumFractionDigits = 0
    return formatter
}

// MARK: - Colors & Styling

func suitColor(suit: String) -> Color {
    switch suit.lowercased() {
    case "h", "d": return .red
    case "c", "s": return .white // Use white for dark mode
    default: return .gray
    }
}

func suitColorForCard(_ card: String?) -> Color? {
    guard let card = card, card.count == 2 else { return nil }
    let suit = String(card.suffix(1))
    return suitColor(suit: suit)
}

// Helper for suit symbols (Now Global)
func suitSymbol(suit: String) -> String {
     switch suit.lowercased() {
     case "h": return "♥️"
     case "d": return "♦️"
     case "c": return "♣️"
     case "s": return "♠️"
     default: return "?"
     }
 }

// Custom Button Style for Cards (can be defined here or in Components)
struct CardButtonStyle: ButtonStyle {
    let suitColor: Color?
    let isSelected: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(suitColor ?? .gray)
            .background(
                ZStack {
                    (isSelected ? Color.green.opacity(0.4) : Color.black.opacity(0.3))
                    if configuration.isPressed {
                        Color.white.opacity(0.1)
                    }
                }
            )
            .cornerRadius(5)
             .overlay(
                 RoundedRectangle(cornerRadius: 5)
                     .stroke(isSelected ? Color.green : Color.white.opacity(0.2), lineWidth: 1)
             )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.2), value: isSelected)
    }
} 