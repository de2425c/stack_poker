// MARK: - Save Home Game Session View

import SwiftUI
import FirebaseAuth
import PhotosUI
import Combine
import Foundation
import FirebaseFirestore

struct SaveHomeGameSessionView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var sessionStore: SessionStore

    let buyIn: Double
    let cashOut: Double
    let duration: TimeInterval
    let date: Date
    let gameName: String
    let gameStakes: String

    @State private var sessionName: String = ""
    @State private var sessionStakes: String = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var showErrorAlert = false
    @State private var showSuccessAnimation = false
    
    var body: some View {
        ZStack {
            // Background
            AppBackgroundView()
                .ignoresSafeArea()
            
            // Main content
            VStack(spacing: 0) {
                // Modern navigation header
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                            Text("Cancel")
                                .font(.system(size: 17))
                        }
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    Text("Save Session")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: saveSession) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .frame(width: 16, height: 16)
                        } else {
                            Text("Save")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(width: 60, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(isFormValid ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color.gray.opacity(0.3))
                    )
                    .disabled(!isFormValid || isSaving)
                    .animation(.easeInOut(duration: 0.2), value: isFormValid)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
                
                // Scroll content
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 32) {
                        // Hero section with session summary
                        heroSectionView
                        
                        // Session details card
                        sessionDetailsCard
                        
                        // Input form
                        inputFormCard
                        
                        // Save button (mobile-friendly)
                        saveButtonView
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            
            // Success animation overlay
            if showSuccessAnimation {
                successOverlay
            }
            
            // Loading overlay
            if isSaving {
                loadingOverlay
            }
        }
        .alert("Error Saving Session", isPresented: $showErrorAlert) {
            Button("OK") { }
        } message: {
            Text(error ?? "An unknown error occurred.")
        }
        .onTapGesture {
            hideKeyboard()
        }
        .onAppear {
            // Pre-fill the form with game data
            if sessionName.isEmpty {
                sessionName = gameName
            }
            if sessionStakes.isEmpty {
                sessionStakes = gameStakes
            }
        }
        .ignoresSafeArea(.keyboard)
    }
    
    // MARK: - Computed Properties
    
    private var isFormValid: Bool {
        !sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !sessionStakes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // MARK: - View Components
    
    private var heroSectionView: some View {
        VStack(spacing: 16) {
            // Icon and title
            VStack(spacing: 12) {
                Image(systemName: "trophy.circle.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    .shadow(color: Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.3), radius: 8, x: 0, y: 4)
                
                Text("Session Complete")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Save this session to your poker tracker")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            
            // Quick stats
            HStack(spacing: 24) {
                quickStatView(
                    icon: "clock.fill",
                    value: formatDuration(duration),
                    label: "Duration",
                    color: .blue
                )
                
                quickStatView(
                    icon: "dollarsign.circle.fill",
                    value: formatMoney(buyIn),
                    label: "Buy-in",
                    color: .orange
                )
                
                quickStatView(
                    icon: "arrow.up.right.circle.fill",
                    value: formatMoney(cashOut),
                    label: "Cash Out",
                    color: Color(red: 123/255, green: 255/255, blue: 99/255)
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.2),
                                    Color.clear,
                                    Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
    }
    
    private func quickStatView(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
    
    private var sessionDetailsCard: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Text("SESSION BREAKDOWN")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Spacer()
            }
            
            // Details grid
            VStack(spacing: 16) {
                detailRow(
                    icon: "banknote.fill",
                    label: "Buy-in",
                    value: formatMoney(buyIn),
                    color: .orange
                )
                
                detailRow(
                    icon: "arrow.up.right.circle.fill",
                    label: "Cash Out",
                    value: formatMoney(cashOut),
                    color: .blue
                )
                
                detailRow(
                    icon: "clock.badge.fill",
                    label: "Session Time",
                    value: formatDuration(duration),
                    color: .purple
                )
                
                detailRow(
                    icon: "calendar.circle.fill",
                    label: "Date",
                    value: formatDate(date),
                    color: .cyan
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private func detailRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(label)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private var inputFormCard: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Text("SESSION DETAILS")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Spacer()
            }
            
            // Form inputs
            VStack(spacing: 20) {
                // Session name input
                ModernInputField(
                    icon: "gamecontroller.fill",
                    title: "Session Name",
                    text: $sessionName,
                    placeholder: "Friday Night Game"
                )
                
                // Stakes input
                ModernInputField(
                    icon: "dollarsign.circle.fill",
                    title: "Stakes",
                    text: $sessionStakes,
                    placeholder: "1/2 NLH"
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var saveButtonView: some View {
        Button(action: saveSession) {
            HStack(spacing: 12) {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                    
                    Text("Save Session")
                        .font(.system(size: 18, weight: .semibold))
                }
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFormValid ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color.gray.opacity(0.3))
                    .shadow(
                        color: isFormValid ? Color(red: 123/255, green: 255/255, blue: 99/255).opacity(0.3) : Color.clear,
                        radius: 12,
                        x: 0,
                        y: 6
                    )
            )
        }
        .disabled(!isFormValid || isSaving)
        .animation(.easeInOut(duration: 0.2), value: isFormValid)
        .animation(.easeInOut(duration: 0.2), value: isSaving)
    }
    
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64, weight: .medium))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                    .scaleEffect(showSuccessAnimation ? 1.0 : 0.5)
                    .animation(.spring(response: 0.6, dampingFraction: 0.6), value: showSuccessAnimation)
                
                Text("Session Saved!")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(showSuccessAnimation ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.4).delay(0.2), value: showSuccessAnimation)
            }
        }
        .transition(.opacity)
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 123/255, green: 255/255, blue: 99/255)))
                    .scaleEffect(1.5)
                
                Text("Saving Session...")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.3), radius: 30, x: 0, y: 15)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
    
    // MARK: - Helper Functions
    
    private func formatMoney(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount))"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        guard duration > 0 else { return "0m" }
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func saveSession() {
        guard isFormValid else { return }
        
        isSaving = true
        error = nil
        
        guard let userId = Auth.auth().currentUser?.uid else {
            DispatchQueue.main.async {
                self.error = "Failed to get user ID"
                self.showErrorAlert = true
                self.isSaving = false
            }
            return
        }
        
        let sessionData: [String: Any] = [
            "userId": userId,
            "gameType": "Home Game",
            "gameName": sessionName.trimmingCharacters(in: .whitespacesAndNewlines),
            "stakes": sessionStakes.trimmingCharacters(in: .whitespacesAndNewlines),
            "startDate": Timestamp(date: date.addingTimeInterval(-duration)),
            "startTime": Timestamp(date: date.addingTimeInterval(-duration)),
            "endTime": Timestamp(date: date),
            "hoursPlayed": duration / 3600,
            "buyIn": buyIn,
            "cashout": cashOut,
            "profit": cashOut - buyIn,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        sessionStore.addSession(sessionData) { saveError in
            DispatchQueue.main.async {
                self.isSaving = false
                if let saveError = saveError {
                    self.error = "Failed to save session: \(saveError.localizedDescription)"
                    self.showErrorAlert = true
                } else {
                    // Show success animation
                    withAnimation(.easeInOut(duration: 0.3)) {
                        self.showSuccessAnimation = true
                    }
                    
                    // Dismiss after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Modern Input Field

struct ModernInputField: View {
    let icon: String
    let title: String
    @Binding var text: String
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
                
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 123/255, green: 255/255, blue: 99/255))
            }
            
            TextField("", text: $text)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder)
                        .foregroundColor(.white.opacity(0.5))
                }
                .font(.system(size: 17))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isFocused ? Color(red: 123/255, green: 255/255, blue: 99/255) : Color.white.opacity(0.1),
                                    lineWidth: isFocused ? 2 : 1
                                )
                        )
                )
                .focused($isFocused)
                .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
}

// MARK: - Extensions


