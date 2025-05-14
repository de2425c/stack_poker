import SwiftUI

struct SearchBarView: View {
    @Binding var searchText: String
    var placeholder: String
    var onSearch: () -> Void
    var onClear: () -> Void
    
    @State private var isEditing = false
    
    var body: some View {
        HStack {
            // Search field with icon
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .padding(.leading, 8)
                
                TextField(placeholder, text: $searchText, onEditingChanged: { editing in
                    self.isEditing = editing
                }, onCommit: {
                    onSearch()
                })
                .padding(8)
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                
                // Clear button
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        onClear()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                }
            }
            .background(Color.black.opacity(0.3))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            // Cancel button when editing
            if isEditing {
                Button("Cancel") {
                    searchText = ""
                    isEditing = false
                    UIApplication.shared.endEditing()
                    onClear()
                }
                .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                .padding(.leading, 10)
                .transition(.move(edge: .trailing))
                .animation(.default, value: isEditing)
            }
        }
        .padding(.horizontal)
    }
}

// Extension to dismiss keyboard
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// Preview
struct SearchBarView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            SearchBarView(
                searchText: .constant(""),
                placeholder: "Search for people",
                onSearch: {},
                onClear: {}
            )
        }
    }
} 