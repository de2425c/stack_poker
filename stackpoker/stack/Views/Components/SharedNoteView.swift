import SwiftUI

struct SharedNoteView: View {
    let note: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Note header with label
            HStack {
                Text("Note")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(4)
                
                Spacer()
            }
            
            // Horizontal divider
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(height: 1)
            
            // Note content
            Text(note)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
        }
        .padding(16)
        .background(Color(red: 30/255, green: 33/255, blue: 36/255))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    SharedNoteView(note: "Really feeling good about my game today. Been focusing on position play and it's paying off.")
        .previewLayout(.sizeThatFits)
        .background(Color.black)
        .padding()
} 