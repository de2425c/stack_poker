import SwiftUI
import FirebaseFirestore

struct SessionsCalendarView: View {
    @ObservedObject var sessionStore: SessionStore
    @Binding var selectedDate: Date? // Use binding from parent
    @State private var currentMonth: Date
    
    // Initializer to set currentMonth
    init(sessionStore: SessionStore, selectedDate: Binding<Date?>) {
        self.sessionStore = sessionStore
        self._selectedDate = selectedDate
        self._currentMonth = State(initialValue: selectedDate.wrappedValue ?? Date())
    }
    
    // Get PNL for each day in current month
    private var dailyPNL: [String: Double] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var pnlByDate: [String: Double] = [:]
        
        // CORRECT: Loop through ALL sessions, not just the current month's
        for session in sessionStore.sessions {
            let dateKey = formatter.string(from: session.startDate)
            pnlByDate[dateKey, default: 0] += session.profit
        }
        
        return pnlByDate
    }
    
    // Get session count for each day
    private var dailySessionCount: [String: Int] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var countByDate: [String: Int] = [:]
        
        // CORRECT: Loop through ALL sessions, not just the current month's
        for session in sessionStore.sessions {
            let dateKey = formatter.string(from: session.startDate)
            countByDate[dateKey, default: 0] += 1
        }
        
        return countByDate
    }
    
    // Calculate total PNL for current month
    private var monthlyPNL: Double {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        var total: Double = 0
        
        for session in sessionStore.sessions {
            if calendar.isDate(session.startDate, equalTo: currentMonth, toGranularity: .month) {
                total += session.profit
            }
        }
        
        return total
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                monthNavigationHeader
                calendarGrid
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .onAppear {
            if sessionStore.sessions.isEmpty {
                sessionStore.fetchSessions()
            }
        }
    }
    
    // MARK: - Month Navigation Header
    private var monthNavigationHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(monthYearString)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(formatMonthlyPNL(monthlyPNL))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(monthlyPNL >= 0 ? .green : .red)
                }
                
                Spacer()
                
                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                }
            }
        }
    }
    
    // MARK: - Calendar Grid
    private var weekdaySymbols: [String] {
        return ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }
    
    private func generateDaysInMonthGrid() -> [Date?] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else { return [] }
        
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: currentMonth)!.count
        
        // Get the weekday of the first day (1 = Sunday, 2 = Monday, etc.)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        
        // Convert to Monday-first indexing (Monday = 0, Sunday = 6)
        let mondayFirstWeekday = (firstWeekday == 1) ? 6 : firstWeekday - 2
        
        var days: [Date?] = []
        
        // Add empty slots for days before the first day of the month
        for _ in 0..<mondayFirstWeekday {
            days.append(nil)
        }
        
        // Add all days of the month
        for day in 1...daysInMonth {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) {
                days.append(date)
            }
        }
        
        return days
    }
    
    private var calendarGrid: some View {
        VStack(spacing: 10) {
            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { daySymbol in
                    Text(daySymbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Calendar days
            let days = generateDaysInMonthGrid()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days.indices, id: \.self) { index in
                    if let date = days[index] {
                        let calendar = Calendar.current
                        let dayComponent = calendar.component(.day, from: date)
                        let isSelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)
                        let pnl = getPNL(for: date)
                        let sessionCount = getSessionCount(for: date)
                        let isToday = calendar.isDateInToday(date)
                        
                        SessionCalendarDayView(
                            day: dayComponent,
                            isSelected: isSelected,
                            pnl: pnl,
                            sessionCount: sessionCount,
                            isToday: isToday,
                            onTap: {
                                if sessionCount > 0 {
                                    if let selected = selectedDate, calendar.isDate(selected, inSameDayAs: date) {
                                        selectedDate = nil
                                    } else {
                                        selectedDate = date
                                    }
                                }
                            }
                        )
                    } else {
                        Text("")
                            .frame(height: 48)
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getPNL(for date: Date) -> Double {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        return dailyPNL[dateKey] ?? 0
    }
    
    private func getSessionCount(for date: Date) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateKey = formatter.string(from: date)
        return dailySessionCount[dateKey] ?? 0
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM, yyyy"
        return formatter.string(from: currentMonth)
    }
    
    private func formatMonthlyPNL(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        
        if amount >= 0 {
            return formatter.string(from: NSNumber(value: amount)) ?? "$0"
        } else {
            let positiveAmount = abs(amount)
            let formatted = formatter.string(from: NSNumber(value: positiveAmount)) ?? "0"
            return "-\(formatted)"
        }
    }
    
    private func previousMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentMonth = newDate
            }
        }
    }
    
    private func nextMonth() {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentMonth = newDate
            }
        }
    }
}

// MARK: - Session Calendar Day View
struct SessionCalendarDayView: View {
    let day: Int
    let isSelected: Bool
    let pnl: Double
    let sessionCount: Int
    let isToday: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(textColor)
                
                if sessionCount > 0 && pnl != 0 {
                    Text(formatPNL(pnl))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.white : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(sessionCount == 0)
    }
    
    private var backgroundColor: Color {
        if sessionCount > 0 {
            if pnl > 0 {
                return Color(red: 0.2, green: 0.7, blue: 0.2) // Green for profits
            } else if pnl < 0 {
                return Color(red: 0.6, green: 0.2, blue: 0.2) // Red for losses
            } else {
                return Color.gray.opacity(0.3) // Gray for break-even
            }
        } else if isToday {
            return Color.blue.opacity(0.2)
        } else {
            return Color.clear
        }
    }
    
    private var textColor: Color {
        if sessionCount > 0 {
            return .white
        } else if isToday {
            return .blue
        } else {
            return .white.opacity(0.6)
        }
    }
    
    private func formatPNL(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        
        if amount >= 0 {
            return formatter.string(from: NSNumber(value: amount)) ?? "$0"
        } else {
            let positiveAmount = abs(amount)
            let formatted = formatter.string(from: NSNumber(value: positiveAmount)) ?? "0"
            return "-\(formatted)"
        }
    }
}

 