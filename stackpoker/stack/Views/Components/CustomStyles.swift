import SwiftUI

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .foregroundColor(.white)
            .font(.custom("PlusJakartaSans-Regular", size: 16))
            .frame(height: 56)
            .autocapitalization(.none) // Default to no auto-capitalization
    }
} 