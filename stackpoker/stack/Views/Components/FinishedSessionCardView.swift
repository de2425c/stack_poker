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
    
    // Computed property to determine if this is a tournament
    var isTournament: Bool {
        stakes.lowercased().contains("tournament") || 
        stakes.lowercased().contains("buy-in") ||
        stakes.contains("$") && !stakes.contains("/")
    }
    
    // Computed property for stakes display
    var stakesDisplay: String {
        if isTournament {
            return "$\(String(format: "%.0f", buyIn)) Buy-In"
        } else {
            return stakes
        }
    }
    
    // Environment for detecting dark mode
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Rich glossy black background
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.black.opacity(0.95),
                                Color(UIColor(red: 20/255, green: 20/255, blue: 25/255, alpha: 1.0)),
                                Color.black.opacity(0.98)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.2),
                                        Color.white.opacity(0.05),
                                        Color.clear
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 15, x: 0, y: 8)
                
                VStack(alignment: .center, spacing: 0) {
                    // Top section with centered logo
                    VStack(alignment: .center, spacing: 20) {
                        // Stack logo - bigger and centered
                        Image("stack_logo")
                            .resizable()
                            .renderingMode(.template)
                            .foregroundColor(.white)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 140, height: 140)
                            .padding(.top, 30)
                        
                        // Game name only - centered and larger
                        AdaptiveText(gameName, maxLines: 2, availableWidth: geometry.size.width - 40, fontName: "PlusJakartaSans-Bold", baseFontSize: 50, maxFontSize: 80, minFontSize: 24, color: .white)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: geometry.size.width - 40) // Constrain width

                        // Stakes Display - Only show for cash games, not tournaments
                        if !isTournament {
                            AdaptiveText(
                                stakesDisplay,
                                maxLines: 1,
                                availableWidth: geometry.size.width - 60,
                                fontName: "PlusJakartaSans-Medium",
                                baseFontSize: 28,
                                maxFontSize: 36,
                                minFontSize: 20,
                                color: .white.opacity(0.8)
                            )
                            .padding(.top, 5)
                            .frame(maxWidth: geometry.size.width - 60) // Constrain width
                        }
                    }
                    
                    Spacer()
                    
                    // Financial information
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("BUY-IN")
                                    .font(.custom("PlusJakartaSans-Medium", size: 18))
                                    .foregroundColor(.white.opacity(0.8))
                                Text("\(currencySymbol)\(String(format: "%.2f", buyIn))")
                                    .font(.custom("PlusJakartaSans-Bold", size: 24))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 6) {
                                Text("CASH OUT")
                                    .font(.custom("PlusJakartaSans-Medium", size: 18))
                                    .foregroundColor(.white.opacity(0.8))
                                Text("\(currencySymbol)\(String(format: "%.2f", cashOut))")
                                    .font(.custom("PlusJakartaSans-Bold", size: 24))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Divider line
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                            .padding(.vertical, 12)
                        
                        // Duration and Profit
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DURATION")
                                    .font(.custom("PlusJakartaSans-Medium", size: 18))
                                    .foregroundColor(.white.opacity(0.8))
                                Text(duration.uppercased())
                                    .font(.custom("PlusJakartaSans-Bold", size: 22))
                                    .foregroundColor(.white)
                            }
                            
                            Spacer()
                            
                            // Large profit/loss display
                            Text("\(profit >= 0 ? "+" : "")\(String(format: "%.2f", profit))")
                                .font(.custom("PlusJakartaSans-Bold", size: min(geometry.size.width * 0.18, 72)))
                                .foregroundColor(profit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : Color.red)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 30)
                }
            }
        }
        .aspectRatio(0.8, contentMode: .fit) // Taller card proportions
        .frame(minHeight: 400) // Minimum height to ensure it's large enough
    }
}

// Enhanced preview provider
struct FinishedSessionCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Winning session preview
            FinishedSessionCardView(
                gameName: "WYNN 1/2",
                stakes: "$200.00",
                location: "Home Game",
                date: Date(),
                duration: "5H",
                buyIn: 200.00,
                cashOut: 560.00
            )
            .frame(width: 350, height: 450)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray.opacity(0.1))
            .previewDisplayName("Winning Session")
            
            // Losing session preview
            FinishedSessionCardView(
                gameName: "PLO High Stakes Tournament",
                stakes: "$2/$5",
                location: "Bellagio",
                date: Date(),
                duration: "2h 45m",
                buyIn: 500.00,
                cashOut: 379.25
            )
            .frame(width: 350, height: 450)
            .preferredColorScheme(.dark)
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray.opacity(0.1))
            .previewDisplayName("Losing Session - Dark Mode")
        }
    }
} 
