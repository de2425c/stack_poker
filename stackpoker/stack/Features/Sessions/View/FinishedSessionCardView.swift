import SwiftUI

// A completely re-architected luxury share card.
// This version uses a robust, asymmetrical layout to prevent text clipping.
struct FinishedSessionCardView: View {
    // MARK: - Data
    let gameName: String
    let stakes: String
    let date: Date // Retained for potential future use
    let duration: String
    let buyIn: Double
    let cashOut: Double
    let isBackgroundTransparent: Bool
    var onEditTitle: (() -> Void)? = nil // Optional callback for editing title
    var onTitleChanged: ((String) -> Void)? = nil // Optional callback for title changes
    
    // MARK: - State
    @State private var showingEditAlert = false
    @State private var editedTitle: String = ""

    // MARK: - Derived Properties
    private var profit: Double { cashOut - buyIn }
    private var profitColor: Color { profit < 0 ? .red : .green }
    // This now correctly formats negative profit with K/M logic, e.g., "-$250", "$1.2K", "$1.5M"
    private var formattedProfit: String {
        let absProfit = abs(profit)
        let sign = profit < 0 ? "-" : ""
        
        if absProfit >= 1000000 {
            let millions = absProfit / 1000000
            return "\(sign)$\(String(format: "%.1f", millions))M"
        } else if absProfit >= 10000 {
            let thousands = absProfit / 1000
            return "\(sign)$\(String(format: "%.1f", thousands))K"
        } else {
            return "\(sign)$\(Int(absProfit))"
        }
    }
    private var formattedBuyIn: String { "$\(Int(buyIn))" }
    private var formattedCashOut: String { "$\(Int(cashOut))" }
    
    // Round time to closest hour for cleaner display
    private var roundedDuration: String {
        // Extract hours and minutes from duration string (e.g., "4H 15M")
        let components = duration.uppercased().components(separatedBy: " ")
        guard components.count >= 2,
              let firstComponent = components.first else {
            return duration.uppercased()
        }
        
        let hoursStr = firstComponent.replacingOccurrences(of: "H", with: "")
        let minutesStr = components[1].replacingOccurrences(of: "M", with: "")
        
        guard let hours = Int(hoursStr),
              let minutes = Int(minutesStr) else {
            return duration.uppercased()
        }
        
        // Round to nearest hour
        let totalMinutes = hours * 60 + minutes
        let roundedHours = Int(round(Double(totalMinutes) / 60.0))
        
        return "\(roundedHours)H"
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            // Background with a subtle, premium border
            AppBackgroundView()
                .opacity(isBackgroundTransparent ? 0.0 : 1.0)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(isBackgroundTransparent ? 0.0 : 0.12), lineWidth: 1.5)
                )

            GeometryReader { geo in
                // Main content layout, without the logo
                VStack(alignment: .leading, spacing: 0) {
                    
                    // Top Section: Game Title & Net Profit
                    HStack(alignment: .top, spacing: 0) {
                        // Title block with wrapping text and edit button
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 8) {
                                // Always show title text (no inline editing)
                                Text(gameName.uppercased())
                                    .font(.system(size: 22, weight: .heavy))
                                    .foregroundColor(.white)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .onTapGesture {
                                        showEditAlert()
                                    }
                                
                                if onEditTitle != nil || onTitleChanged != nil {
                                    Button(action: {
                                        showEditAlert()
                                    }) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                            .frame(width: 20, height: 20)
                                            .background(
                                                Circle()
                                                    .fill(Color.white.opacity(0.1))
                                            )
                                    }
                                }
                            }
                            
                            Text(stakes)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer(minLength: 16)

                        // Profit display with a dedicated width to prevent clipping
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("NET")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .tracking(1)
                            Text(formattedProfit)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundColor(profitColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(minWidth: 100, maxWidth: 120) // Fixed width to prevent cutoff
                    }

                    Spacer()

                    // Bottom Metrics Row - logo is now separate
                    HStack(spacing: 24) {
                        MetricView(label: "BUY-IN", value: formattedBuyIn)
                        MetricView(label: "CASHOUT", value: formattedCashOut)
                        MetricView(label: "TIME", value: roundedDuration)
                        Spacer() // Pushes metrics to the left
                    }
                }
                .padding(24)
            }
            
            // Logo overlay, positioned with hardcoded padding for reliability
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image("promo_logo")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundColor(.white.opacity(0.9))
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 70, height: 70)
                }
            }
            .padding(.bottom, 1) // Nudge up from the bottom
            .padding(.trailing, 30) // Nudge in from the right
        }
        .frame(width: 350, height: 220) // A beautiful, balanced rectangle
        .onAppear {
            editedTitle = gameName
        }
        .alert("Edit Game Name", isPresented: $showingEditAlert) {
            TextField("Game name", text: $editedTitle)
            Button("Cancel", role: .cancel) {
                editedTitle = gameName // Reset to original
            }
            Button("Save") {
                saveTitle()
            }
        } message: {
            Text("Enter a new name for this game")
        }
    }
    
    // MARK: - Helper Functions
    private func showEditAlert() {
        editedTitle = gameName
        showingEditAlert = true
    }
    
    private func saveTitle() {
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            onTitleChanged?(trimmedTitle)
        }
    }
}

// MARK: - Reusable Metric View
private struct MetricView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        FinishedSessionCardView(
            gameName: "Wynn",
            stakes: "$2/$5 No-Limit Hold'em",
            date: Date(),
            duration: "4H 15M",
            buyIn: 500,
            cashOut: 1280,
            isBackgroundTransparent: false
        )
        FinishedSessionCardView(
            gameName: "No-Limit Hold'em Tournament",
            stakes: "$3000 Guaranteed",
            date: Date(),
            duration: "2H 30M",
            buyIn: 250,
            cashOut: 0, // This will now show "-$250"
            isBackgroundTransparent: false
        )
        FinishedSessionCardView(
            gameName: "NLH Tournament",
            stakes: "$250 Buy-in NLH",
            date: Date(),
            duration: "4H 15M",
            buyIn: 500,
            cashOut: 250, // Example of a loss
            isBackgroundTransparent: true
        )
    }
    .padding()
    .background(Color.black)
}
