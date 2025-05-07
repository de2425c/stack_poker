import SwiftUI
import FirebaseFirestore

struct SessionSummaryRow: View {
    let session: Session
    
    private func formatMoney(_ amount: Double) -> String {
        return "$\(Int(amount))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Game Info and Profit/Loss
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(session.gameName) - \(session.stakes)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text(formatDate(session.startDate))
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                Spacer()
                Text(session.profit > 0 ? "+$\(Int(session.profit))" : "-$\(abs(Int(session.profit)))")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(session.profit > 0 ? .green : .red)
            }
            
            // Session Details
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(format: "%.1f", session.hoursPlayed)) hours")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Text("\(formatTime(session.startTime)) - \(formatTime(session.endTime))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Buy-in: \(formatMoney(session.buyIn))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                    Text("Cashout: \(formatMoney(session.cashout))")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1.0)),
                            Color(UIColor(red: 32/255, green: 32/255, blue: 34/255, alpha: 1.0))
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.05)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 4, y: 2)
        )
    }
} 