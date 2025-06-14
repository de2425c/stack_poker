import SwiftUI

// Custom adaptive text view that scales based on content and available space
struct AdaptiveText: View {
    let text: String
    let maxLines: Int
    let availableWidth: CGFloat
    let fontName: String
    let baseFontSize: CGFloat
    let maxFontSize: CGFloat
    let minFontSize: CGFloat
    let color: Color
    
    init(
        _ text: String,
        maxLines: Int = 2,
        availableWidth: CGFloat,
        fontName: String = "PlusJakartaSans-Bold",
        baseFontSize: CGFloat = 40,
        maxFontSize: CGFloat = 64,
        minFontSize: CGFloat = 20,
        color: Color = .white
    ) {
        self.text = text
        self.maxLines = maxLines
        self.availableWidth = availableWidth
        self.fontName = fontName
        self.baseFontSize = baseFontSize
        self.maxFontSize = maxFontSize
        self.minFontSize = minFontSize
        self.color = color
    }
    
    var body: some View {
        Text(text.uppercased())
            .font(.custom(fontName, size: adaptiveFontSize))
            .foregroundColor(color)
            .lineLimit(maxLines)
            .minimumScaleFactor(0.3)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    private var adaptiveFontSize: CGFloat {
        // Start with a larger size for shorter text
        let wordCount = text.split(separator: " ").count
        let characterCount = text.count
        
        var fontSize: CGFloat
        
        // Base sizing logic - more aggressive sizing but width-aware
        if wordCount <= 2 && characterCount <= 15 {
            // Short text gets much larger font
            fontSize = maxFontSize
        } else if wordCount <= 4 && characterCount <= 30 {
            // Medium text gets larger font
            fontSize = baseFontSize * 1.2
        } else {
            // Longer text gets base font
            fontSize = baseFontSize
        }
        
        // Width-based adjustment - be more conservative if text is very long
        let estimatedCharWidth = fontSize * 0.6 // Rough estimate of character width
        let estimatedTextWidth = Double(characterCount) * estimatedCharWidth / Double(maxLines)
        
        if estimatedTextWidth > availableWidth * 0.9 { // Leave 10% margin
            // Text is likely too wide, reduce font size
            fontSize = fontSize * 0.75
        }
        
        // Ensure it's within bounds
        fontSize = min(fontSize, maxFontSize)
        fontSize = max(fontSize, minFontSize)
        
        return fontSize
    }
}

struct FinishedSessionCardView: View {
    // Session data
    let gameName: String
    let stakes: String
    let location: String
    let date: Date
    let duration: String
    let buyIn: Double
    let cashOut: Double
    let currencySymbol: String = "$"
    
    // Computed property for profit/loss
    var profit: Double {
        cashOut - buyIn
    }
    
    private var profitColor: Color {
        profit >= 0 ? .green : .red
    }
    
    private var profitString: String {
        return "$\(Int(abs(profit)))"
    }
    
    // Determine if tournament or cash game
    private var gameType: String {
        if stakes.lowercased().contains("tournament") || 
           stakes.lowercased().contains("buy-in") ||
           (stakes.contains("$") && !stakes.contains("/")) {
            return "TOURNAMENT"
        } else {
            return "CASH GAME"
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppBackgroundView()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                VStack(spacing: 0) {
                    // Top section with logo and game info
                    VStack(spacing: 16) {
                        Image("promo_logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 44, height: 44)
                            .foregroundColor(.white.opacity(0.95))
                        
                        VStack(spacing: 6) {
                            AdaptiveGameTitle(
                                gameName, 
                                availableWidth: geometry.size.width - 48
                            )
                            
                            Text(stakes)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 20)
                    
                    // Metrics section with perfect spacing
                    HStack(spacing: 0) {
                        VStack(spacing: 16) {
                            LuxuryMetric(label: "BUY-IN", value: "$\(Int(buyIn))")
                            LuxuryMetric(label: "TIME", value: duration.uppercased())
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(spacing: 16) {
                            LuxuryMetric(label: "CASHOUT", value: "$\(Int(cashOut))")
                            LuxuryMetric(label: "DATE", value: dateFormatter.string(from: date).uppercased())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 32)
                    
                    Spacer(minLength: 24)
                    
                    // Net result section
                    VStack(spacing: 8) {
                        Text("NET RESULT")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.65))
                            .tracking(1.2)
                        
                        Text(profitString)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(profitColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .aspectRatio(1.35, contentMode: .fit)
        .frame(maxWidth: 340, maxHeight: 252)
    }
}

// MARK: - AdaptiveGameTitle Component
struct AdaptiveGameTitle: View {
    let text: String
    let availableWidth: CGFloat
    
    init(_ text: String, availableWidth: CGFloat) {
        self.text = text
        self.availableWidth = availableWidth
    }
    
    private var fontSize: CGFloat {
        let characterCount = text.count
        
        if characterCount <= 6 {
            return min(24, availableWidth * 0.09)
        } else if characterCount <= 10 {
            return min(22, availableWidth * 0.08)
        } else if characterCount <= 15 {
            return min(20, availableWidth * 0.07)
        } else {
            return min(18, availableWidth * 0.065)
        }
    }
    
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .tracking(0.5)
    }
}

// MARK: - LuxuryMetric Component
struct LuxuryMetric: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
    }
}

// Enhanced preview provider
struct FinishedSessionCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Cash game preview
            FinishedSessionCardView(
                gameName: "WYNN 1/2",
                stakes: "$1/$2 NL Hold'em",
                location: "Wynn Las Vegas",
                date: Date(),
                duration: "5H",
                buyIn: 200.00,
                cashOut: 560.00
            )
            .frame(width: 280, height: 400)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray.opacity(0.1))
            .previewDisplayName("Cash Game")
            
            // Tournament preview
            FinishedSessionCardView(
                gameName: "Daily Deepstack",
                stakes: "$150 Buy-in Tournament",
                location: "Bellagio",
                date: Date(),
                duration: "4H 30M",
                buyIn: 150.00,
                cashOut: 425.00
            )
            .frame(width: 280, height: 400)
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray.opacity(0.1))
            .previewDisplayName("Tournament")
        }
    }
} 
