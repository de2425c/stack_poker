import SwiftUI

// Enhanced session card - more minimal version
struct EnhancedSessionSummaryRow: View {
    let session: Session
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var showingActions = false
    
    private let actionButtonWidth: CGFloat = 80
    private let maxOffset: CGFloat = -180 // Adjusted for extra spacing
    
    private func formatMoney(_ amount: Double) -> String {
        return "$\(abs(Int(amount)))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"  // Shorter date format
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            // Background action buttons (shown when swiped)
            if showingActions {
                HStack {
                    Spacer()
                    
                    // Edit button
                    Button(action: {
                        resetPosition()
                        onSelect()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 18, weight: .medium))
                            Text("Edit")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: actionButtonWidth)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.25, green: 0.61, blue: 1.0), // #409CFF
                                            Color(red: 0.39, green: 0.71, blue: 1.0)  // #64B4FF
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .padding(.leading, 10) // Added padding to prevent overlap
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Delete button
                    Button(action: {
                        resetPosition()
                        onDelete() // Directly call delete without confirmation
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 18, weight: .medium))
                            Text("Delete")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(width: actionButtonWidth)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(red: 0.85, green: 0.3, blue: 0.3))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.trailing, 4)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
            
            // Main session card content
            HStack(alignment: .center) {
                // Game info with icon removed
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.gameName)
                        .font(.plusJakarta(.body, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(.white)
                    
                    Text(session.stakes)
                        .font(.plusJakarta(.footnote, weight: .medium)) // Using Plus Jakarta Sans
                        .foregroundColor(Color.gray.opacity(0.8))
                }
                
                Spacer()
                
                // Profit amount
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatMoney(session.profit))
                        .font(.plusJakarta(.title3, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(session.profit >= 0 ? 
                                      Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                      Color.red)
                        .padding(.bottom, 2)
                    
                    // Date and hours in one line
                    HStack(spacing: 6) {
                        Text(formatDate(session.startDate))
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                        
                        Text("•")
                            .font(.plusJakarta(.caption)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.5))
                        
                        Text("\(String(format: "%.1f", session.hoursPlayed))h")
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(
                ZStack { // Applying GlassyInputField style to session rows
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Material.ultraThinMaterial)
                        .opacity(0.2)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.01))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5) // Subtle border
                }
            )
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Only handle horizontal drags that are clearly horizontal
                        let translation = value.translation
                        let isDragHorizontal = abs(translation.width) > abs(translation.height) && abs(translation.width) > 10
                        
                        if isDragHorizontal && translation.width < 0 { // Only allow left swipes
                            offset = max(translation.width, maxOffset)
                        }
                    }
                    .onEnded { value in
                        let translation = value.translation
                        let velocity = value.velocity
                        let isDragHorizontal = abs(translation.width) > abs(translation.height) && abs(translation.width) > 10
                        
                        if isDragHorizontal {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if translation.width < -50 || velocity.width < -300 {
                                    // Show actions
                                    offset = maxOffset
                                    showingActions = true
                                } else {
                                    // Reset to original position
                                    resetPosition()
                                }
                            }
                        } else {
                            // Reset position if it wasn't a clear horizontal drag
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                resetPosition()
                            }
                        }
                    }
            )
            .onTapGesture {
                if showingActions {
                    resetPosition()
                } else {
                    hapticFeedback(style: .light)
                    onSelect()
                }
            }
            .contextMenu {
                Button(action: onSelect) {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .clipped()
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showingActions)
    }
    
    private func resetPosition() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = 0
            showingActions = false
        }
    }
    
    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

extension EnhancedSessionSummaryRow {
    func formatCurrency(_ amount: Double) -> String {
        if amount >= 0 {
            return "+$\(Int(amount))"
        } else {
            return "-$\(abs(Int(amount)))"
        }
    }
}

// Beautiful animated empty state
struct EmptySessionsView: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 70))
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.3)))
                .padding(.top, 30)
                .scaleEffect(isAnimating ? 1.0 : 0.9)
                .shadow(color: Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 0.15)), radius: 10, x: 0, y: 5)
            
            Text("No Sessions Recorded")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Start tracking your poker sessions to see your progress and analyze your performance")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .opacity(isAnimating ? 1.0 : 0.0)
                .offset(y: isAnimating ? 0 : 10)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Enhanced section header
struct EnhancedItemsSection: View {
    let title: String
    let items: [SessionOrTransaction]
    let onSelect: (Session) -> Void
    let onDelete: (Session) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.85))
                
                Spacer()
                
                Text("\(items.count) items")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.gray.opacity(0.7))
            }
            .padding(.horizontal, 8)
            
            // Items in this section
            VStack(spacing: 12) {
                ForEach(items) { item in
                    switch item {
                    case .session(let session):
                        EnhancedSessionSummaryRow(
                            session: session,
                            onSelect: { onSelect(session) },
                            onDelete: { onDelete(session) }
                        )
                    case .transaction(let transaction):
                        BankrollTransactionRow(transaction: transaction)
                    }
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Bankroll Transaction Row
struct BankrollTransactionRow: View {
    let transaction: BankrollTransaction
    
    private func formatMoney(_ amount: Double) -> String {
        return "$\(abs(Int(amount)))"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"  // Shorter date format
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"  // Time format
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with bankroll info and amount
            HStack(alignment: .center) {
                // Bankroll adjustment info
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bankroll Adjustment")
                        .font(.plusJakarta(.body, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(.white)
                    
                    if let note = transaction.note, !note.isEmpty {
                        Text(note)
                            .font(.plusJakarta(.footnote, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.8))
                            .lineLimit(2)
                    } else {
                        Text("Manual adjustment")
                            .font(.plusJakarta(.footnote, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Amount and time
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatMoney(transaction.amount))
                        .font(.plusJakarta(.title3, weight: .bold)) // Using Plus Jakarta Sans
                        .foregroundColor(transaction.amount >= 0 ? 
                                      Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                                      Color.red)
                        .padding(.bottom, 2)
                    
                    // Date and time in one line
                    HStack(spacing: 6) {
                        Text(formatDate(transaction.timestamp))
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                        
                        Text("•")
                            .font(.plusJakarta(.caption)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.5))
                        
                        Text(formatTime(transaction.timestamp))
                            .font(.plusJakarta(.caption, weight: .medium)) // Using Plus Jakarta Sans
                            .foregroundColor(Color.gray.opacity(0.7))
                    }
                }
                .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(
            ZStack { // Applying GlassyInputField style to transaction rows
                RoundedRectangle(cornerRadius: 12)
                    .fill(Material.ultraThinMaterial)
                    .opacity(0.2)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.01))
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5) // Subtle border
            }
        )
        .contentShape(Rectangle())
    }
}

// MARK: - SessionWrapper for sheet presentation
struct SessionWrapper: Identifiable {
    let id: String
    let session: Session
    
    init(session: Session) {
        self.id = session.id
        self.session = session
    }
}

extension SessionOrTransaction {
    var date: Date {
        switch self {
        case .session(let session):
            return session.startDate
        case .transaction(let transaction):
            return transaction.timestamp
        }
    }
    
    var amount: Double {
        switch self {
        case .session(let session):
            return session.profit
        case .transaction(let transaction):
            return transaction.amount
        }
    }
}

// MARK: - Session or Transaction enum
enum SessionOrTransaction: Identifiable {
    case session(Session)
    case transaction(BankrollTransaction)
    
    var id: String {
        switch self {
        case .session(let session):
            return "session_\(session.id)"
        case .transaction(let transaction):
            return "transaction_\(transaction.id)"
        }
    }
}
