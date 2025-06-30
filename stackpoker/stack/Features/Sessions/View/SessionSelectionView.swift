import SwiftUI

struct SessionSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var sessionStore: SessionStore
    var onSessionSelected: (Session) -> Void

    var body: some View {
        NavigationView {
            VStack {
                if sessionStore.sessions.isEmpty {
                    Text("No completed sessions found.")
                        .foregroundColor(.gray)
                        .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(sessionStore.sessions) { session in
                            Button(action: {
                                onSessionSelected(session)
                                dismiss()
                            }) {
                                SessionInfoCard(session: session)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        }
                    }
                    .listStyle(PlainListStyle())
                    .background(Color.clear)
                }
            }
            .background(AppBackgroundView().ignoresSafeArea())
            .navigationTitle("Select Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                if sessionStore.sessions.isEmpty {
                    sessionStore.fetchSessions() // Fetch if empty, might already be populated
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(session: Session) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(session.gameName) - \(session.stakes)")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Date: \(session.startTime, style: .date)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text(String(format: "Duration: %.1f hrs", session.hoursPlayed))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "$%.2f", session.profit))
                    .font(.headline)
                    .foregroundColor(session.profit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                Text("Buy-in: $\(Int(session.buyIn))")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Cashout: $\(Int(session.cashout))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct SessionInfoCard: View {
    let session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(session.gameName) - \(session.stakes)")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("Date: \(session.startTime, style: .date)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Text(String(format: "Duration: %.1f hrs", session.hoursPlayed))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "$%.2f", session.profit))
                    .font(.headline)
                    .foregroundColor(session.profit >= 0 ? Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : .red)
                Text("Buy-in: $\(Int(session.buyIn))")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Cashout: $\(Int(session.cashout))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
        )
    }
} 