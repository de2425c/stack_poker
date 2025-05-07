import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct HandVerificationView: View {
    let originalText: String
    let parsedHand: ParsedHandHistory
    let onComplete: (Bool) -> Void
    
    @State private var editedHand: ParsedHandHistory
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    init(originalText: String, parsedHand: ParsedHandHistory, onComplete: @escaping (Bool) -> Void) {
        self.originalText = originalText
        self.parsedHand = parsedHand
        self.onComplete = onComplete
        
        // Initialize the edited hand as a copy of the parsed hand
        _editedHand = State(initialValue: parsedHand)
    }
    
    var body: some View {
        ZStack {
            AppBackgroundView()
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Verify Hand")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Hand Summary Display with editable binding
                        HandSummaryDisplay(hand: $editedHand)
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 16)
                }
                
                // Action buttons
                HStack(spacing: 16) {
                    Button(action: { onComplete(false) }) {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(red: 0.2, green: 0.2, blue: 0.22))
                            )
                    }
                    
                    Button(action: saveTrainingData) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Save")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 123/255, green: 255/255, blue: 99/255))
                    )
                    .disabled(isSaving)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func saveTrainingData() {
        isSaving = true
        
        Task {
            do {
                // Create the training data record - with default quality rating and no notes
                let trainingData = [
                    "originalText": originalText,
                    "parsedHand": try JSONSerialization.jsonObject(with: JSONEncoder().encode(editedHand.raw), options: []),
                    "quality": 5, // Default to high quality
                    "notes": "",
                    "timestamp": Timestamp(),
                    "userId": Auth.auth().currentUser?.uid ?? ""
                ] as [String: Any]
                
                // Save to Firestore
                try await Firestore.firestore().collection("handTrainingData").addDocument(data: trainingData)
                
                // Call onComplete with success
                DispatchQueue.main.async {
                    isSaving = false
                    onComplete(true)
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                    showingError = true
                    isSaving = false
                }
            }
        }
    }
}

// No component definition needed here - using the one from HandSummaryDisplay.swift 