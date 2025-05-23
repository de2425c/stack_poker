import SwiftUI
import FirebaseFirestore

struct EditSessionSheetView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var sessionStore: SessionStore
    let session: Session
    
    @State private var buyInText: String
    @State private var cashOutText: String
    @State private var hoursText: String

    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    init(session: Session, sessionStore: SessionStore) {
        self.session = session
        self.sessionStore = sessionStore
        _buyInText = State(initialValue: String(format: "%.0f", session.buyIn))
        _cashOutText = State(initialValue: String(format: "%.0f", session.cashout))
        _hoursText = State(initialValue: String(format: "%.1f", session.hoursPlayed))
    }

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom Header
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white)
                        .padding()
                    Spacer()
                    Text("Edit Session")
                        .font(.plusJakarta(.headline, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button("Save") { saveChanges() }
                        .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                        .padding()
                }
                .padding(.horizontal) // Padding for the HStack itself
                .frame(height: 50) // Give header a defined height
                .background(Color.black.opacity(0.2)) // Subtle header background

                // Form Content
                ScrollView {
                    VStack(spacing: 0) { // Outer VStack for Spacers
                        Spacer(minLength: 20) // Pushes content down a bit from the header
                        
                        VStack(spacing: 25) { // VStack for the input fields
                            GlassyInputField(icon: "dollarsign.circle", title: "Buy-in Amount") {
                                TextField("e.g., 300", text: $buyInText)
                                    .keyboardType(.decimalPad)
                                    .font(.plusJakarta(.title2, weight: .bold))
                                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .padding(.vertical, 8)
                            }
                            
                            GlassyInputField(icon: "dollarsign.circle.fill", title: "Cash-out Amount") {
                                TextField("e.g., 550", text: $cashOutText)
                                    .keyboardType(.decimalPad)
                                    .font(.plusJakarta(.title2, weight: .bold))
                                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .padding(.vertical, 8)
                            }
                            
                            GlassyInputField(icon: "clock", title: "Session Duration (Hours)") {
                                TextField("e.g., 4.5", text: $hoursText)
                                    .keyboardType(.decimalPad)
                                    .font(.plusJakarta(.title2, weight: .bold))
                                    .foregroundColor(Color(UIColor(red: 123/255, green: 255/255, blue: 99/255, alpha: 1.0)))
                                    .padding(.vertical, 8)
                            }
                        }
                        .padding() // Padding for the group of input fields
                        
                        Spacer() // Pushes the input fields group towards the vertical center/bottom if content is short
                    }
                    // Apply a minHeight to the ScrollView's content to ensure Spacers work effectively
                    // even if the input fields themselves don't take up much space.
                    // This is a bit of a trick to help with vertical centering when keyboard is not present.
                    .frame(minHeight: UIScreen.main.bounds.height * 0.6) // Example: 60% of screen height
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
        // .ignoresSafeArea(.keyboard, edges: .bottom) // This can be added to the ZStack if needed
    }

    private func saveChanges() {
        guard let buyIn = Double(buyInText), 
              let cashOut = Double(cashOutText), 
              let hours = Double(hoursText) else {
            alertTitle = "Invalid Input"
            alertMessage = "Please ensure buy-in, cash-out, and duration are valid numbers."
            showAlert = true
            return
        }
        
        if buyIn < 0 || cashOut < 0 || hours < 0 {
            alertTitle = "Invalid Input"
            alertMessage = "Amounts and duration cannot be negative."
            showAlert = true
            return
        }

        let updatedData: [String: Any] = [
            "buyIn": buyIn,
            "cashout": cashOut,
            "hoursPlayed": hours,
            "profit": cashOut - buyIn, 
            "updatedAt": FieldValue.serverTimestamp() 
        ]
        
        sessionStore.updateSessionDetails(sessionId: session.id, updatedData: updatedData) { error in
            if let error = error {
                alertTitle = "Error"
                alertMessage = "Failed to save changes: \(error.localizedDescription)"
                showAlert = true
            } else {
                dismiss()
            }
        }
    }
} 
