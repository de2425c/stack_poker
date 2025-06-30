import SwiftUI

struct ManualStakerFormFields: View {
    @ObservedObject var manualStakerService: ManualStakerService
    let userId: String
    var onStakerCreated: (ManualStakerProfile) -> Void
    
    @State private var name: String = ""
    @State private var contactInfo: String = ""
    @State private var notes: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String? = nil
    
    @FocusState private var isNameFocused: Bool
    
    private let primaryTextColor: Color = .white
    private let secondaryTextColor: Color = .white.opacity(0.7)
    private let glassOpacity: Double = 0.1
    private let materialOpacity: Double = 0.3
    
    var body: some View {
        VStack(spacing: 16) {
            // Name field (required)
            GlassyInputField(
                icon: "person.fill",
                title: "Staker Name *",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                TextField("Enter staker's name...", text: $name)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .focused($isNameFocused)
                    .onSubmit {
                        // Move to next field or create if ready
                        if isValidInput {
                            createStaker()
                        }
                    }
            }
            
            // Contact info field (optional)
            GlassyInputField(
                icon: "phone.fill",
                title: "Contact Info (Optional)",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                TextField("Phone, email, or other contact...", text: $contactInfo)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
            }
            
            // Notes field (optional)
            GlassyInputField(
                icon: "note.text",
                title: "Notes (Optional)",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                TextField("Any additional notes...", text: $notes, axis: .vertical)
                    .font(.plusJakarta(.body, weight: .regular))
                    .foregroundColor(primaryTextColor)
                    .lineLimit(3...6)
            }
            
            // Error message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.plusJakarta(.caption, weight: .medium))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Create button
            Button(action: createStaker) {
                HStack {
                    if isCreating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "person.fill.badge.plus")
                        Text("Create Staker Profile")
                    }
                }
                .font(.plusJakarta(.body, weight: .bold))
                .foregroundColor(.black)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isValidInput ? Color.white : Color.gray.opacity(0.5))
                )
            }
            .disabled(!isValidInput || isCreating)
            
            Spacer(minLength: 50)
        }
        .onAppear {
            // Focus on name field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFocused = true
            }
        }
    }
    
    private var isValidInput: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func createStaker() {
        guard isValidInput else { return }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for duplicate names
        if manualStakerService.hasExistingProfile(name: trimmedName, userId: userId) {
            errorMessage = "A staker with this name already exists"
            return
        }
        
        isCreating = true
        errorMessage = nil
        
        let newProfile = ManualStakerProfile(
            createdByUserId: userId,
            name: trimmedName,
            contactInfo: contactInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : contactInfo.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        Task {
            do {
                _ = try await manualStakerService.createManualStaker(newProfile)
                
                await MainActor.run {
                    onStakerCreated(newProfile)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create staker profile: \(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    ManualStakerFormFields(
        manualStakerService: ManualStakerService(),
        userId: "test",
        onStakerCreated: { _ in }
    )
    .background(AppBackgroundView())
} 