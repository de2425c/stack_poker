import SwiftUI

// MARK: - Sessions Tab
struct SessionsTab: View {
    @ObservedObject var sessionStore: SessionStore
    @ObservedObject var bankrollStore: BankrollStore
    @EnvironmentObject private var userService: UserService
    @State private var showingDeleteAlert = false
    @State private var selectedSession: Session? = nil
    @State private var showEditSheet = false
    @State private var editBuyIn = ""
    @State private var editCashout = ""
    @State private var editHours = ""
    @State private var selectedDate: Date? = nil

    private var selectedDateFormatted: String {
        guard let date = selectedDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Combined sessions and transactions grouped by time periods
    private var groupedItems: (today: [SessionOrTransaction], lastWeek: [SessionOrTransaction], older: [SessionOrTransaction]) {
        let calendar = Calendar.current
        
        // Filter sessions if a date is selected
        let sessionsToDisplay: [Session]
        if let date = selectedDate {
            sessionsToDisplay = sessionStore.sessions.filter { session in
                calendar.isDate(session.startDate, inSameDayAs: date)
            }
        } else {
            sessionsToDisplay = sessionStore.sessions
        }
        
        // Also filter transactions if a date is selected
        let transactionsToDisplay: [BankrollTransaction]
        if let date = selectedDate {
            transactionsToDisplay = bankrollStore.transactions.filter {
                calendar.isDate($0.timestamp, inSameDayAs: date)
            }
        } else {
            transactionsToDisplay = bankrollStore.transactions
        }
        
        let sessionItems = sessionsToDisplay.map { SessionOrTransaction.session($0) }
        let transactionItems = transactionsToDisplay.map { SessionOrTransaction.transaction($0) }
        
        let allItems = (sessionItems + transactionItems).sorted { item1, item2 in
            item1.date > item2.date
        }
        
        if selectedDate != nil {
            return (today: allItems, lastWeek: [], older: [])
        }
        
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday)!
        
        var today: [SessionOrTransaction] = []
        var lastWeek: [SessionOrTransaction] = []
        var older: [SessionOrTransaction] = []
        
        for item in allItems {
            if calendar.isDate(item.date, inSameDayAs: now) {
                today.append(item)
            } else if item.date >= oneWeekAgo && item.date < startOfToday {
                lastWeek.append(item)
            } else {
                older.append(item)
            }
        }
        
        return (today, lastWeek, older)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Add top padding and remove side padding to fix squeezing
            SessionsCalendarView(sessionStore: sessionStore, selectedDate: $selectedDate)
                .padding(.top, 30)
                .padding(.bottom, 10)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let date = selectedDate {
                        if groupedItems.today.isEmpty {
                            VStack {
                                Spacer(minLength: 50)
                                Text("No sessions recorded on")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text(selectedDateFormatted)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            EnhancedItemsSection(
                                title: "Sessions for \(selectedDateFormatted)", 
                                items: groupedItems.today, 
                                onSelect: { session in selectedSession = session },
                                onDelete: { session in
                                    sessionStore.deleteSession(session.id) { error in
                                        if let error = error {
                                            print("Error deleting session: \(error)")
                                        }
                                    }
                                }
                            )
                            .padding(.horizontal, 16)
                        }
                    } else {
                        VStack(spacing: 22) {
                            if !groupedItems.today.isEmpty {
                                EnhancedItemsSection(title: "Today", items: groupedItems.today, onSelect: { session in selectedSession = session }, onDelete: { session in
                                    sessionStore.deleteSession(session.id) { error in
                                        if let error = error {
                                            print("Error deleting session: \(error)")
                                        }
                                    }
                                })
                                .padding(.horizontal, 16)
                            }
                            
                            if !groupedItems.lastWeek.isEmpty {
                                EnhancedItemsSection(title: "Last Week", items: groupedItems.lastWeek, onSelect: { session in selectedSession = session }, onDelete: { session in
                                    sessionStore.deleteSession(session.id) { error in
                                        if let error = error {
                                            print("Error deleting session: \(error)")
                                        }
                                    }
                                })
                                .padding(.horizontal, 16)
                            }
                            
                            if !groupedItems.older.isEmpty {
                                EnhancedItemsSection(title: "All Time", items: groupedItems.older, onSelect: { session in selectedSession = session }, onDelete: { session in
                                    sessionStore.deleteSession(session.id) { error in
                                        if let error = error {
                                            print("Error deleting session: \(error)")
                                        }
                                    }
                                })
                                .padding(.horizontal, 16)
                            }
                            
                            if sessionStore.sessions.isEmpty && bankrollStore.transactions.isEmpty {
                                EmptySessionsView()
                                    .padding(32)
                            }
                        }
                    }
                    
                    // Add significant bottom padding to ensure content is not cut off
                    Color.clear
                        .frame(height: 80)
                }
            }
            .scrollIndicators(.visible)
        }
        .background(AppBackgroundView().ignoresSafeArea())
        .sheet(item: Binding<SessionWrapper?>(
            get: { selectedSession.map(SessionWrapper.init) },
            set: { _ in selectedSession = nil }
        )) { sessionWrapper in
            NavigationView {
                SessionDetailView(session: sessionWrapper.session)
                    .environmentObject(sessionStore)
                    .environmentObject(userService)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Done") {
                                selectedSession = nil
                            }
                            .foregroundColor(.white)
                        }
                    }
            }
        }
    }
}