import SwiftUI

// MARK: - Session Timer Display
struct SessionTimerDisplay: View {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            // Hours
            TimeUnit(value: hours, unit: "h", showColon: true)
            
            // Minutes
            TimeUnit(value: minutes, unit: "m", showColon: true)
            
            // Seconds
            TimeUnit(value: seconds, unit: "s", showColon: false)
        }
        .opacity(isActive ? 1.0 : 0.7)
    }
}

// MARK: - Individual Time Unit
struct TimeUnit: View {
    let value: Int
    let unit: String
    let showColon: Bool
    
    var body: some View {
        HStack(spacing: 2) {
            Text("\(String(format: "%02d", value))")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            if showColon {
                Text(":")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
            } else {
                Text(unit)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.leading, 2)
            }
        }
    }
}

// MARK: - Action Button
struct ActionButton: View {
    let icon: String
    let title: String
    let backgroundColor: Color
    let borderColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(14)
        }
    }
}

// MARK: - Chip Stack Graph
struct ChipStackGraph: View {
    let amounts: [Double]
    let startAmount: Double
    
    private var maxAmount: Double {
        max(startAmount, (amounts.max() ?? startAmount) * 1.1)
    }
    
    private var minAmount: Double {
        min(startAmount, (amounts.min() ?? startAmount) * 0.9)
    }
    
    private var range: Double {
        maxAmount - minAmount
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Chip Stack")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Current change from starting stack
                let lastAmount = amounts.last ?? startAmount
                let change = lastAmount - startAmount
                let isProfit = change >= 0
                
                Text(String(format: "%@$%.0f", isProfit ? "+" : "", change))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isProfit ? 
                        Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)) : 
                        Color.red)
            }
            
            // Graph view
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
                    
                    // Starting line
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                        .offset(y: geometry.size.height * (1 - ((startAmount - minAmount) / range)))
                    
                    // Graph line
                    Path { path in
                        guard !amounts.isEmpty else { return }
                        
                        let stepX = geometry.size.width / CGFloat(max(1, amounts.count - 1))
                        
                        // Start at initial buy-in
                        path.move(to: CGPoint(
                            x: 0,
                            y: geometry.size.height * (1 - ((startAmount - minAmount) / range))
                        ))
                        
                        // Connect each point
                        for (index, amount) in amounts.enumerated() {
                            let point = CGPoint(
                                x: CGFloat(index) * stepX,
                                y: geometry.size.height * (1 - ((amount - minAmount) / range))
                            )
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 123/255, green: 255/255, blue: 99/255),
                                Color(red: 100/255, green: 200/255, blue: 255/255)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                    
                    // Amount labels
                    VStack(alignment: .leading) {
                        Text("$\(Int(maxAmount))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Spacer()
                        
                        Text("$\(Int(startAmount))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Spacer()
                        
                        Text("$\(Int(minAmount))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                }
            }
            .frame(height: 120)
        }
    }
}

// MARK: - Note Card
struct NoteCard: View {
    let text: String
    let timestamp: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Note content
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
            
            // Timestamp
            Text(formattedTime)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Input Field
struct SessionInputField: View {
    let icon: String
    let placeholdText: String
    @Binding var text: String
    let onSubmit: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.gray)
            
            TextField("", text: $text)
                .placeholder(when: text.isEmpty) {
                    Text(placeholdText)
                        .foregroundColor(.gray.opacity(0.7))
                }
                .foregroundColor(.white)
                .font(.system(size: 15))
            
            Button(action: onSubmit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            .disabled(text.isEmpty)
            .opacity(text.isEmpty ? 0.5 : 1.0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 25/255, green: 28/255, blue: 32/255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// Helper for placeholder
extension View {
    func placeholds<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholds: () -> Content
    ) -> some View {
        ZStack(alignment: alignment) {
            placeholds().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - Update Card
struct SessionUpdateCard: View {
    let title: String
    let description: String
    let timestamp: Date
    let isPosted: Bool
    let onPost: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(formattedTime)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            // Content
            Text(description)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
            
            // Action button
            if !isPosted {
                Button(action: onPost) {
                    HStack {
                        Spacer()
                        
                        Text("Share to Feed")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .background(
                        Color.gray.opacity(0.3)
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 30/255, green: 33/255, blue: 36/255))
        )
        .overlay(
            isPosted ?
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1) :
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: timestamp)
    }
}

// MARK: - Stack Update Action Sheet
struct StackUpdateSheet: View {
    @Binding var isPresented: Bool
    @Binding var chipAmount: String
    @Binding var noteText: String
    let onSubmit: (String, String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Update Stack")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
            }
            
            // Chip amount field
            VStack(alignment: .leading, spacing: 8) {
                Text("CURRENT CHIPS")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                HStack {
                    Text("$")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.gray)
                    
                    TextField("Amount", text: $chipAmount)
                        .keyboardType(.numberPad)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 25/255, green: 28/255, blue: 32/255))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            
            Spacer()
            
            // Submit button
            Button(action: {
                onSubmit(chipAmount, "")  // Passing empty note
                isPresented = false
                chipAmount = ""
            }) {
                Text("Update Stack")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(red: 25/255, green: 28/255, blue: 32/255))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                    )
            }
            .disabled(chipAmount.isEmpty)
            .opacity(chipAmount.isEmpty ? 0.5 : 1)
        }
        .padding(24)
        .background(
            Color(red: 18/255, green: 20/255, blue: 24/255)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Hand History Input
struct HandHistoryInputSheet: View {
    @Binding var isPresented: Bool
    @Binding var handText: String
    let onSubmit: (String) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Add Hand History")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                }
            }
            
            // Hand history text field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("HAND HISTORY")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("Paste or type")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                
                ZStack(alignment: .topLeading) {
                    if handText.isEmpty {
                        Text("Paste your hand history here...")
                            .foregroundColor(.gray.opacity(0.7))
                            .padding(.leading, 5)
                            .padding(.top, 8)
                    }
                    
                    TextEditor(text: $handText)
                        .foregroundColor(.white)
                        .font(.system(size: 14, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(5)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 25/255, green: 28/255, blue: 32/255))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            
            Spacer()
            
            // Submit button
            Button(action: {
                onSubmit(handText)
                isPresented = false
                handText = ""
            }) {
                Text("Save Hand")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(red: 25/255, green: 28/255, blue: 32/255))
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                    )
            }
            .disabled(handText.isEmpty)
            .opacity(handText.isEmpty ? 0.5 : 1)
        }
        .padding(24)
        .background(
            Color(red: 18/255, green: 20/255, blue: 24/255)
                .ignoresSafeArea()
        )
    }
} 
