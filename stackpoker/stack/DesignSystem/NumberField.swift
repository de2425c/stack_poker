import SwiftUI

// MARK: - UI Components

struct NumberField: View {
    let title: String
    @Binding var value: Double
    var prefix: String = ""
    
    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0 // No decimals for stacks/blinds typically
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
            
            HStack {
                if !prefix.isEmpty {
                    Text(prefix)
                        .foregroundColor(.white)
                }
                
                TextField("", value: $value, formatter: numberFormatter)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(RoundedTextFieldStyle()) // Apply reusable style
            }
        }
    }
} 