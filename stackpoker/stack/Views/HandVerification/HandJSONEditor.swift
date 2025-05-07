import SwiftUI

// This component allows editing the raw JSON of a parsed hand history
struct HandJSONEditor: View {
    @Binding var hand: ParsedHandHistory
    @Binding var isEditing: Bool
    @State private var jsonText: String = ""
    @State private var jsonError: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("JSON Data")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: {
                    if isEditing {
                        applyChanges()
                    }
                    isEditing.toggle()
                }) {
                    Text(isEditing ? "Apply" : "Edit")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isEditing ? Color.green.opacity(0.7) : Color.blue.opacity(0.7))
                        .cornerRadius(6)
                }
            }
            
            if let error = jsonError {
                Text(error)
                    .font(.system(size: 14))
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
            }
            
            ScrollView {
                if isEditing {
                    TextEditor(text: $jsonText)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(minHeight: 400)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                } else {
                    Text(jsonText)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                }
            }
            .frame(height: 400)
        }
        .onAppear {
            formatJSON()
        }
    }
    
    private func formatJSON() {
        do {
            let handData = try JSONEncoder().encode(hand.raw)
            
            // Format the JSON with indentation for readability
            let jsonObject = try JSONSerialization.jsonObject(with: handData)
            let prettyData = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted])
            
            if let formattedString = String(data: prettyData, encoding: .utf8) {
                jsonText = formattedString
            }
            
            jsonError = nil
        } catch {
            jsonText = "Error formatting JSON: \(error.localizedDescription)"
            jsonError = error.localizedDescription
        }
    }
    
    private func applyChanges() {
        guard let jsonData = jsonText.data(using: .utf8) else {
            jsonError = "Unable to convert text to data"
            return
        }
        
        do {
            // Parse JSON string to data structure
            let decoder = JSONDecoder()
            let rawHand = try decoder.decode(RawHandHistory.self, from: jsonData)
            hand = ParsedHandHistory(raw: rawHand)
            jsonError = nil
        } catch {
            jsonError = "Invalid JSON: \(error.localizedDescription)"
        }
    }
} 