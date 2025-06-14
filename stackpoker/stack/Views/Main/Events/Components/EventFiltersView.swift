import SwiftUI

struct EventFiltersView: View {
    @Binding var selectedDate: SimpleDate?
    @Binding var selectedBuyinRange: BuyinRange
    @Binding var selectedSeriesSet: Set<String>
    
    let availableDates: [IdentifiableSimpleDate]
    let availableSeries: [String]
    let currentSystemDate: SimpleDate
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Date Selection
                        filterSection(title: "Date") {
                            dateSelectionView
                        }
                        
                        // Buy-in Range Selection
                        filterSection(title: "Buy-in Range") {
                            buyinRangeView
                        }
                        
                        // Series Selection
                        if !availableSeries.isEmpty {
                            filterSection(title: "Series") {
                                seriesSelectionView
                            }
                        }
                        
                        // Clear All Button
                        VStack(spacing: 12) {
                            Button(action: clearAllFilters) {
                                Text("Clear All Filters")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            
                            Button(action: { dismiss() }) {
                                Text("Apply Filters")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 64/255, green: 156/255, blue: 255/255),
                                                Color(red: 100/255, green: 180/255, blue: 255/255)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(
                trailing: Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
            )
        }
    }
    
    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            content()
        }
    }
    
    private var dateSelectionView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(futureDates) { identifiableDate in
                        let isSelected = selectedDate == identifiableDate.simpleDate
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedDate = identifiableDate.simpleDate
                            }
                        }) {
                            VStack(spacing: 6) {
                                Text(identifiableDate.simpleDate.displayMedium)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                
                                if isSelected {
                                    Circle()
                                        .fill(Color(red: 64/255, green: 156/255, blue: 255/255))
                                        .frame(width: 4, height: 4)
                                } else {
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 4, height: 4)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 80)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                isSelected ? Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.6) : Color.white.opacity(0.1), 
                                                lineWidth: isSelected ? 1.5 : 0.5
                                            )
                                    )
                            )
                            .scaleEffect(isSelected ? 1.02 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(identifiableDate.simpleDate)
                    }
                }
                .padding(.horizontal, 4)
            }
            .onAppear {
                // Default to current date if no date is selected or if selected date is in the past
                let targetDate: SimpleDate
                if let selected = selectedDate, selected >= currentSystemDate {
                    targetDate = selected
                } else {
                    targetDate = currentSystemDate
                    selectedDate = currentSystemDate // Update the binding to current date
                }
                
                if futureDates.contains(where: { $0.simpleDate == targetDate }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(targetDate, anchor: .center)
                        }
                    }
                } else if let firstFutureDate = futureDates.first?.simpleDate {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            proxy.scrollTo(firstFutureDate, anchor: .center)
                        }
                    }
                }
            }
        }
    }
    
    // Computed property to filter out past dates
    private var futureDates: [IdentifiableSimpleDate] {
        availableDates.filter { $0.simpleDate >= currentSystemDate }
    }
    
    private var buyinRangeView: some View {
        VStack(spacing: 8) {
            ForEach(BuyinRange.allCases, id: \.id) { range in
                Button(action: {
                    selectedBuyinRange = range
                }) {
                    HStack {
                        Text(range.rawValue)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if selectedBuyinRange == range {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedBuyinRange == range ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedBuyinRange == range ? Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }
    
    private var seriesSelectionView: some View {
        VStack(spacing: 8) {
            // All Series option
            Button(action: {
                selectedSeriesSet.removeAll()
            }) {
                HStack {
                    Text("All Series")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if selectedSeriesSet.isEmpty {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selectedSeriesSet.isEmpty ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selectedSeriesSet.isEmpty ? Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
            }
            
            // Individual series
            ForEach(availableSeries, id: \.self) { series in
                Button(action: {
                    if selectedSeriesSet.contains(series) {
                        selectedSeriesSet.remove(series)
                    } else {
                        selectedSeriesSet.insert(series)
                    }
                }) {
                    HStack {
                        Text(series)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        if selectedSeriesSet.contains(series) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedSeriesSet.contains(series) ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(selectedSeriesSet.contains(series) ? Color(red: 64/255, green: 156/255, blue: 255/255).opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }
    
    private func clearAllFilters() {
        selectedDate = nil  // Let the parent view handle date selection logic
        selectedBuyinRange = .all
        selectedSeriesSet.removeAll()
    }
}

#Preview {
    EventFiltersView(
        selectedDate: .constant(nil),
        selectedBuyinRange: .constant(.all),
        selectedSeriesSet: .constant(Set<String>()),
        availableDates: [],
        availableSeries: ["WSOP", "WPT", "EPT"],
        currentSystemDate: SimpleDate(year: 2025, month: 6, day: 5)
    )
} 