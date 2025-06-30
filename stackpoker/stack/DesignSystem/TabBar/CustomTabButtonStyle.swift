import SwiftUI

// Custom Button Style for Tab Bar Items
struct CustomTabButtonStyle: ButtonStyle {
    var isSelected: Bool
    var title: String
    
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 4) {
            configuration.label
                .font(.system(size: 24))
                .foregroundColor(isSelected ? .white : .gray)
            
            Text(title)
                .font(.caption2)
                .foregroundColor(isSelected ? .white : .gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? Color.gray.opacity(0.2) : Color.clear)
        .cornerRadius(10)
        .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
        .animation(.spring(), value: configuration.isPressed)
    }
} 