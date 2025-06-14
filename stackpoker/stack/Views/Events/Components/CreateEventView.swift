import SwiftUI
import FirebaseAuth
import PhotosUI

struct CreateEventView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var userEventService = UserEventService()
    
    let onEventCreated: ((UserEvent) -> Void)?
    
    // Event form data
    @State private var eventTitle = ""
    @State private var eventDescription = ""
    @State private var eventType: UserEvent.EventType = .homeGame // Preselected
    @State private var isPublic = false // Add public/private toggle
    @State private var startDate = Date().addingTimeInterval(3600) // Default to 1 hour from now
    @State private var endDate: Date?
    @State private var hasEndDate = false
    @State private var location = ""
    @State private var hasLocation = false
    @State private var maxParticipants: String = ""
    @State private var hasMaxParticipants = false
    @State private var waitlistEnabled = true
    
    // Image picker state
    @State private var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var hasImage = false
    
    // UI state
    @State private var isCreating = false
    @State private var error: String?
    @State private var showError = false
    @State private var bankWithStack = false
    @State private var showBankingInfoPopup = false
    
    // Helper computed properties
    private var isFormValid: Bool {
        !eventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        startDate > Date()
    }
    
    private var maxParticipantsInt: Int? {
        if hasMaxParticipants {
            return Int(maxParticipants.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
    
    init(onEventCreated: ((UserEvent) -> Void)? = nil) {
        self.onEventCreated = onEventCreated
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Top spacer for navigation bar clearance
                        Color.clear.frame(height: 80)
                        
                        VStack(spacing: 32) {
                            // Header
                            VStack(spacing: 8) {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 48))
                                    .foregroundColor(.white)
                                
                                Text("Create Event")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Set up your poker event")
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 16)
                            
                            // Event Type Section (only Home Game for now)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Event Type")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                
                                // Home Game Option (only option for now)
                                HStack(spacing: 12) {
                                    Button(action: {
                                        eventType = .homeGame
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "house.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(eventType == .homeGame ? .black : .white)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Home Game")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(eventType == .homeGame ? .black : .white)
                                                
                                                Text("Private poker night")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(eventType == .homeGame ? .black.opacity(0.7) : .gray)
                                            }
                                            
                                            Spacer()
                                            
                                            if eventType == .homeGame {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(eventType == .homeGame ? .white : Color.white.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(eventType == .homeGame ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                
                                // Coming soon hint
                                Text("More event types coming soon")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 16)
                                    .padding(.top, 4)
                            }
                            
                            // Public/Private Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Event Visibility")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                
                                VStack(spacing: 12) {
                                    // Private Option
                                    Button(action: {
                                        isPublic = false
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(!isPublic ? .black : .white)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Private Event")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(!isPublic ? .black : .white)
                                                
                                                Text("Invite only")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(!isPublic ? .black.opacity(0.7) : .gray)
                                            }
                                            
                                            Spacer()
                                            
                                            if !isPublic {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(!isPublic ? .white : Color.white.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(!isPublic ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .padding(.horizontal, 16)
                                    
                                    // Public Option
                                    Button(action: {
                                        isPublic = true
                                    }) {
                                        HStack(spacing: 12) {
                                            Image(systemName: "globe")
                                                .font(.system(size: 18))
                                                .foregroundColor(isPublic ? .black : .white)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Public Event")
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(isPublic ? .black : .white)
                                                
                                                Text("Anyone can find and join")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(isPublic ? .black.opacity(0.7) : .gray)
                                            }
                                            
                                            Spacer()
                                            
                                            if isPublic {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                        .padding(16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(isPublic ? .white : Color.white.opacity(0.08))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(isPublic ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            
                            // Home Game Banking Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Home Game Banking")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)

                                VStack(spacing: 12) {
                                    HStack {
                                        Toggle(isOn: $bankWithStack.animation()) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Bank your home game?")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.white)
                                                Text("Enable chip tracking and requests.")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .toggleStyle(SwitchToggleStyle(tint: .white))
                                        
                                        Button(action: {
                                            showBankingInfoPopup = true
                                        }) {
                                            Image(systemName: "info.circle")
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.bottom, 16)
                            
                            // Event Image Section
                            VStack(spacing: 12) {
                                HStack {
                                    Toggle("Add event image", isOn: $hasImage)
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .toggleStyle(SwitchToggleStyle(tint: .white))
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                
                                if hasImage {
                                    VStack(spacing: 12) {
                                        if let selectedImage = selectedImage {
                                            // Show selected image
                                            VStack(spacing: 8) {
                                                Image(uiImage: selectedImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(height: 120)
                                                    .clipped()
                                                    .cornerRadius(12)
                                                    .padding(.horizontal, 16)
                                                
                                                Button("Change Image") {
                                                    showingImagePicker = true
                                                }
                                                .font(.system(size: 14))
                                                .foregroundColor(.white.opacity(0.8))
                                            }
                                        } else {
                                            // Show image picker button
                                            Button(action: {
                                                showingImagePicker = true
                                            }) {
                                                VStack(spacing: 12) {
                                                    Image(systemName: "photo.badge.plus")
                                                        .font(.system(size: 32))
                                                        .foregroundColor(.white.opacity(0.7))
                                                    
                                                    Text("Choose Event Image")
                                                        .font(.system(size: 16, weight: .medium))
                                                        .foregroundColor(.white)
                                                    
                                                    Text("Add a photo to make your event stand out")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.gray)
                                                        .multilineTextAlignment(.center)
                                                }
                                                .frame(height: 120)
                                                .frame(maxWidth: .infinity)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(Color.white.opacity(0.05))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 12)
                                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                        )
                                                )
                                            }
                                            .padding(.horizontal, 16)
                                        }
                                    }
                                }
                            }
                            
                            // Event Title
                            GlassyInputField(
                                icon: "text.cursor",
                                title: "EVENT TITLE",
                                labelColor: .white
                            ) {
                                TextField("Friday Night Poker", text: $eventTitle)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                            }
                            .padding(.horizontal, 16)
                            
                            // Event Description
                            GlassyInputField(
                                icon: "text.alignleft",
                                title: "DESCRIPTION",
                                labelColor: .white
                            ) {
                                TextField("Tell players about your game...", text: $eventDescription, axis: .vertical)
                                    .font(.system(size: 17))
                                    .foregroundColor(.white)
                                    .padding(.vertical, 10)
                                    .lineLimit(3...6)
                            }
                            .padding(.horizontal, 16)
                            
                            // Date and Time Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Date & Time")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                
                                // Start Date
                                GlassyInputField(
                                    icon: "calendar",
                                    title: "START DATE & TIME",
                                    labelColor: .gray
                                ) {
                                    DatePicker("", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.compact)
                                        .colorScheme(.dark)
                                        .accentColor(.white)
                                        .padding(.vertical, 8)
                                }
                                .padding(.horizontal, 16)
                                
                                // End Date Toggle and Picker
                                VStack(spacing: 12) {
                                    HStack {
                                        Toggle("Set end time", isOn: $hasEndDate)
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .toggleStyle(SwitchToggleStyle(tint: .white))
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    
                                    if hasEndDate {
                                        GlassyInputField(
                                            icon: "calendar.badge.clock",
                                            title: "END DATE & TIME",
                                            labelColor: .gray
                                        ) {
                                            DatePicker("", selection: Binding(
                                                get: { endDate ?? startDate.addingTimeInterval(3600) },
                                                set: { endDate = $0 }
                                            ), displayedComponents: [.date, .hourAndMinute])
                                                .datePickerStyle(.compact)
                                                .colorScheme(.dark)
                                                .accentColor(.white)
                                                .padding(.vertical, 8)
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                }
                            }
                            
                            // Location Section
                            VStack(spacing: 12) {
                                HStack {
                                    Toggle("Add location", isOn: $hasLocation)
                                        .font(.system(size: 16))
                                        .foregroundColor(.white)
                                        .toggleStyle(SwitchToggleStyle(tint: .white))
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                
                                if hasLocation {
                                    GlassyInputField(
                                        icon: "location",
                                        title: "LOCATION",
                                        labelColor: .gray
                                    ) {
                                        TextField("Enter address or venue name", text: $location)
                                            .font(.system(size: 17))
                                            .foregroundColor(.white)
                                            .padding(.vertical, 10)
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            
                            // Player Settings Section
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Player Settings")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                
                                VStack(spacing: 12) {
                                    HStack {
                                        Toggle("Set player limit", isOn: $hasMaxParticipants)
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .toggleStyle(SwitchToggleStyle(tint: .white))
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    
                                    if hasMaxParticipants {
                                        GlassyInputField(
                                            icon: "person.2",
                                            title: "MAXIMUM PLAYERS",
                                            labelColor: .gray
                                        ) {
                                            TextField("8", text: $maxParticipants)
                                                .font(.system(size: 17))
                                                .foregroundColor(.white)
                                                .keyboardType(.numberPad)
                                                .padding(.vertical, 10)
                                        }
                                        .padding(.horizontal, 16)
                                    }
                                    
                                    HStack {
                                        Toggle("Enable waitlist", isOn: $waitlistEnabled)
                                            .font(.system(size: 16))
                                            .foregroundColor(.white)
                                            .toggleStyle(SwitchToggleStyle(tint: .white))
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            
                            // Create Button
                            Button(action: createEvent) {
                                HStack {
                                    if isCreating {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                            .frame(width: 20, height: 20)
                                            .padding(.horizontal, 10)
                                    } else {
                                        Text("Create Event")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.black)
                                            .padding(.horizontal, 20)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(isFormValid && !isCreating ? .white : Color.white.opacity(0.3))
                                )
                            }
                            .disabled(!isFormValid || isCreating)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 60)
                        }
                    }
                }
                .contentShape(Rectangle()) // Makes the entire scroll view tappable
                .onTapGesture {
                    // Dismiss keyboard when tapping anywhere
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(error ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $showingImagePicker) {
                EventImagePicker(selectedImage: $selectedImage)
            }
            .sheet(isPresented: $showBankingInfoPopup) {
                BankingInfoPopupView()
            }
            .ignoresSafeArea(.keyboard)
        }
    }
    
    private func createEvent() {
        guard isFormValid else { return }
        
        isCreating = true
        error = nil
        
        Task {
            do {
                let newEvent = try await userEventService.createEvent(
                    title: eventTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: eventDescription.isEmpty ? nil : eventDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    eventType: eventType, // Use the selected type (which is .homeGame for now)
                    startDate: startDate,
                    endDate: hasEndDate ? endDate : nil,
                    location: hasLocation ? location.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                    maxParticipants: maxParticipantsInt,
                    waitlistEnabled: waitlistEnabled,
                    isPublic: isPublic,
                    rsvpDeadline: nil,
                    image: hasImage ? selectedImage : nil,
                    isBanked: bankWithStack
                )
                
                await MainActor.run {
                    isCreating = false
                    onEventCreated?(newEvent)
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    self.error = "Failed to create event: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

private struct BankingInfoPopupView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Spacer()
                        Text("Stack Banking")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.top, 30)
                    .padding(.bottom, 10)

                    Text("Here's how banking your home game works:")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 20) {
                        infoPoint(number: 1, text: "When you're ready, you'll manually start the banking from the event details page.")
                        infoPoint(number: 2, text: "A Home Game will be created on the Stack app, with you as the owner and all RSVP'd players added automatically.")
                        infoPoint(number: 3, text: "Players can then use the app to submit buy-in and cash-out requests throughout the game.")
                        infoPoint(number: 4, text: "Players who RSVP via email will receive a link to stackpoker.gg, where they can track the game and manage their buy-ins.")
                        infoPoint(number: 5, text: "Once the game is over, a permanent log will be saved in your completed events page.")
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 30)

                    Button(action: {
                        dismiss()
                    }) {
                        Text("Got it!")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func infoPoint(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
                .background(Color.white)
                .clipShape(Circle())

            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.85))
                .lineSpacing(4)
        }
    }
}

// MARK: - Event Image Picker
struct EventImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: EventImagePicker
        
        init(_ parent: EventImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.selectedImage = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.selectedImage = originalImage
            }
            
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}


 