import SwiftUI

// --- Custom SimpleDateHeaderPicker View ---
struct SimpleDateHeaderPicker: View {
    var availableDates: [IdentifiableSimpleDate]
    @Binding var selectedDate: SimpleDate?
    let currentSystemDate: SimpleDate
    // TODO: Pass in font names as parameters if Jakarta is used elsewhere for consistency

    @State private var isExpanded: Bool = false

    private var displayString: String {
        if let date = selectedDate {
            return date.displayMedium
        } else if let firstDate = availableDates.first?.simpleDate {
            return firstDate.displayMedium
        } else {
            return "Select Date"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tappable Header Row
            HStack(spacing: 4) {
                Text("Events On")
                    // TODO: Replace with .font(.custom("YourJakartaFontName-Bold", size: 22))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(displayString) 
                    // TODO: Replace with .font(.custom("YourJakartaFontName-Bold", size: 22))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.gray)
                    .rotationEffect(.degrees(isExpanded ? -180 : 0))
            }
            .padding(.vertical, 8) // Padding for the tappable area
            .contentShape(Rectangle()) // Makes the whole HStack tappable
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }

            // Expanded List of Dates
            if isExpanded {
                ScrollView { // Wrap the list in a ScrollView
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(availableDates) { identifiableDate in
                            let isPastDate = identifiableDate.simpleDate < currentSystemDate
                            Button(action: {
                                if !isPastDate { // Only allow selection if not a past date
                                    self.selectedDate = identifiableDate.simpleDate
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        self.isExpanded = false
                                    }
                                }
                            }) {
                                HStack {
                                    Text(identifiableDate.simpleDate.displayMedium)
                                        // TODO: Replace with .font(.custom("YourJakartaFontName-Regular", size: 16))
                                        .font(.system(size: 16, weight: selectedDate == identifiableDate.simpleDate && !isPastDate ? .bold : .regular, design: .rounded))
                                        .foregroundColor(
                                            isPastDate ? .gray.opacity(0.5) : (selectedDate == identifiableDate.simpleDate ? Color(red: 64/255, green: 156/255, blue: 255/255) : .white.opacity(0.8))
                                        )
                                    Spacer()
                                    if selectedDate == identifiableDate.simpleDate && !isPastDate { // Checkmark only if selected AND not past
                                        Image(systemName: "checkmark")
                                            .foregroundColor(Color(red: 64/255, green: 156/255, blue: 255/255))
                                    }
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 10) // Padding within list items
                                .background(Color.black.opacity(isPastDate ? 0.03 : (selectedDate == identifiableDate.simpleDate ? 0.15 : 0.05))) // Adjust background for past dates
                                .cornerRadius(8)
                            }
                            .disabled(isPastDate) // Disable the button for past dates
                            .padding(.vertical, 2) // Spacing between items
                        }
                    }
                }
                .padding(8) // Padding around the list itself
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor(red: 40/255, green: 42/255, blue: 45/255, alpha: 1.0))) // Darker background for dropdown
                        .shadow(color: .black.opacity(0.3), radius: 5, y: 3)
                )
                // Add maxHeight to the ScrollView itself
                .frame(maxHeight: UIScreen.main.bounds.height * 0.4) // e.g., max 40% of screen height
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                .zIndex(1) // Ensure dropdown appears above other content if needed
            }
        }
    }
}

// --- End Custom SimpleDateHeaderPicker View --- 