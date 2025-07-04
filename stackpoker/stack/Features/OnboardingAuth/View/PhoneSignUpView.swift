import SwiftUI
import FirebaseAuth

struct CountryCode: Equatable {
    let name: String
    let code: String
    let flag: String
    let dialCode: String
}

struct PhoneSignUpView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var phoneNumber = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingPhoneVerification = false
    @State private var showingCountryPicker = false
    @State private var selectedCountry = CountryCode.defaultCountry
    @StateObject private var authService = AuthService()
    
    // Real-time validation states
    @State private var phoneIsValid = false
    @State private var hasInteracted = false
    @State private var agreesToTerms = false
    @State private var showingLegalDocs = false
    
    // Computed property for form validity
    private var isFormValid: Bool {
        phoneIsValid
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    AppBackgroundView()
                        .ignoresSafeArea(.all)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Sign Up with Phone")
                                .font(.custom("PlusJakartaSans-Bold", size: 32))
                                .foregroundColor(.white)
                                .padding(.top, 85)
                            
                            Text("Enter your phone number to get started")
                                .font(.custom("PlusJakartaSans-Regular", size: 16))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.bottom, 4)
                            
                            // Phone Number Registration Form
                            VStack(spacing: 16) {
                                // Country Code Picker
                                Button(action: { showingCountryPicker = true }) {
                                    HStack {
                                        Text(selectedCountry.flag)
                                            .font(.system(size: 24))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(selectedCountry.name)
                                                .font(.custom("PlusJakartaSans-Medium", size: 16))
                                                .foregroundColor(.white)
                                            Text(selectedCountry.dialCode)
                                                .font(.custom("PlusJakartaSans-Regular", size: 14))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.down")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.white.opacity(0.1))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                                }
                                
                                // Phone Number Field with real-time validation
                                GlassyInputField(
                                    icon: "phone", 
                                    title: "PHONE NUMBER", 
                                    labelColor: phoneValidationColor
                                ) {
                                    HStack {
                                        Text(selectedCountry.dialCode)
                                            .font(.plusJakarta(.body))
                                            .foregroundColor(.white.opacity(0.7))
                                        
                                        TextField("", text: $phoneNumber)
                                            .font(.plusJakarta(.body))
                                            .foregroundColor(.white)
                                            .keyboardType(.phonePad)
                                            .textContentType(.telephoneNumber)
                                            .onChange(of: phoneNumber) { newValue in
                                                // Format phone number as user types (without country code)
                                                phoneNumber = formatPhoneNumberForCountry(newValue, countryCode: selectedCountry.code)
                                                validatePhoneNumber(phoneNumber)
                                                if !hasInteracted { hasInteracted = true }
                                            }
                                            .placeholder(when: phoneNumber.isEmpty) {
                                                Text(getPlaceholderForCountry(selectedCountry.code))
                                                    .foregroundColor(.white.opacity(0.5))
                                                    .font(.plusJakarta(.body))
                                            }
                                            .toolbar {
                                                ToolbarItemGroup(placement: .keyboard) {
                                                    Spacer()
                                                    Button("Done") {
                                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                                    }
                                                    .foregroundColor(.blue)
                                                    .fontWeight(.medium)
                                                }
                                            }
                                    }
                                }
                                
                                // Info text about SMS charges and verification
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("We'll send you a verification code via SMS.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Text("You may need to complete a CAPTCHA verification for security.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    Text("Standard message and data rates may apply.")
                                        .font(.custom("PlusJakartaSans-Regular", size: 12))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 4)
                                
                                // Terms and Conditions
                                HStack(alignment: .center, spacing: 12) {
                                    Button(action: {
                                        withAnimation {
                                            agreesToTerms.toggle()
                                        }
                                    }) {
                                        Image(systemName: agreesToTerms ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 24))
                                            .foregroundColor(agreesToTerms ? Color.blue : .gray)
                                    }

                                    (
                                        Text("I agree to the ")
                                            .foregroundColor(.white.opacity(0.7))
                                        +
                                        Text("Terms & Conditions")
                                            .foregroundColor(.blue)
                                            .underline()
                                    )
                                    .font(.plusJakarta(.caption))
                                    .onTapGesture {
                                        showingLegalDocs = true
                                    }
                                }
                                .padding(.vertical, 8)
                                
                                // Send Code Button
                                Button(action: {
                                    // Add haptic feedback for immediate response
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                    impactFeedback.impactOccurred()
                                    sendVerificationCode()
                                }) {
                                    ZStack {
                                        HStack {
                                            if isLoading {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                                    .scaleEffect(0.8)
                                                Text("Sending Code...")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.black)
                                            } else {
                                                Text("Send Verification Code")
                                                    .font(.custom("PlusJakartaSans-SemiBold", size: 18))
                                                    .foregroundColor(.black)
                                            }
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 56)
                                    .animation(.easeInOut(duration: 0.2), value: isLoading)
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 28)
                                        .fill(buttonBackgroundColor)
                                        .scaleEffect(isLoading ? 0.98 : 1.0)
                                        .animation(.easeInOut(duration: 0.1), value: isLoading)
                                )
                                .disabled(isLoading || (!isFormValid && hasInteracted) || !agreesToTerms)
                                .opacity(buttonOpacity)
                                .animation(.easeInOut(duration: 0.2), value: isFormValid)
                                .contentShape(Rectangle())
                            }
                            .padding(.top, 12)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 80) // HARDCODED: Ensure buttons are never blocked by bottom padding
                    }
                    
                    // Close button
                    VStack {
                        HStack {
                            Button(action: { 
                                if !showingPhoneVerification {
                                    dismiss()
                                }
                            }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                            .padding(.leading, 16)
                            .padding(.top, 25)
                            
                            Spacer()
                        }
                        Spacer()
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .navigationBarHidden(true)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
                .font(.custom("PlusJakartaSans-Medium", size: 16))
        }
        .sheet(isPresented: $showingCountryPicker) {
            CountryPickerView(selectedCountry: $selectedCountry)
        }
        .fullScreenCover(isPresented: $showingPhoneVerification) {
            PhoneVerificationView(phoneNumber: getFullPhoneNumber(), authService: authService)
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showingLegalDocs) {
            LegalDocsView()
        }
        .onChange(of: selectedCountry) { _ in
            // Clear phone number when country changes
            phoneNumber = ""
            phoneIsValid = false
        }
    }
    
    // MARK: - Validation Methods
    private func validatePhoneNumber(_ phone: String) {
        // Basic phone number validation - check if it has required digits for the country
        let digitsOnly = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        let minLength = getMinLengthForCountry(selectedCountry.code)
        let maxLength = getMaxLengthForCountry(selectedCountry.code)
        phoneIsValid = digitsOnly.count >= minLength && digitsOnly.count <= maxLength
    }
    
    private func formatPhoneNumberForCountry(_ phone: String, countryCode: String) -> String {
        // Remove all non-numeric characters
        let digitsOnly = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Limit to max length for the country
        let maxLength = getMaxLengthForCountry(countryCode)
        let limitedDigits = String(digitsOnly.prefix(maxLength))
        
        // Apply country-specific formatting
        switch countryCode {
        case "US", "CA":
            return formatUSPhoneNumber(limitedDigits)
        case "GB":
            return formatUKPhoneNumber(limitedDigits)
        case "FR":
            return formatFrenchPhoneNumber(limitedDigits)
        case "DE":
            return formatGermanPhoneNumber(limitedDigits)
        case "JP":
            return formatJapanesePhoneNumber(limitedDigits)
        case "AU":
            return formatAustralianPhoneNumber(limitedDigits)
        default:
            // Generic formatting for other countries
            return formatGenericPhoneNumber(limitedDigits)
        }
    }
    
    private func formatUSPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 7 {
            let areaCode = String(limitedDigits.prefix(3))
            let prefix = String(limitedDigits.dropFirst(3).prefix(3))
            let suffix = String(limitedDigits.dropFirst(6))
            return "(\(areaCode)) \(prefix)-\(suffix)"
        } else if limitedDigits.count >= 4 {
            let areaCode = String(limitedDigits.prefix(3))
            let prefix = String(limitedDigits.dropFirst(3))
            return "(\(areaCode)) \(prefix)"
        } else if limitedDigits.count >= 1 {
            return limitedDigits
        }
        return ""
    }
    
    private func formatUKPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 7 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4).prefix(3))
            let third = String(limitedDigits.dropFirst(7))
            return "\(first) \(second) \(third)"
        } else if limitedDigits.count >= 4 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4))
            return "\(first) \(second)"
        }
        return limitedDigits
    }
    
    private func formatFrenchPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 8 {
            let groups = stride(from: 0, to: limitedDigits.count, by: 2).map { i in
                let start = limitedDigits.index(limitedDigits.startIndex, offsetBy: i)
                let end = limitedDigits.index(start, offsetBy: min(2, limitedDigits.count - i))
                return String(limitedDigits[start..<end])
            }
            return groups.joined(separator: " ")
        }
        return limitedDigits
    }
    
    private func formatGermanPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 6 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3).prefix(3))
            let third = String(limitedDigits.dropFirst(6))
            return "\(first) \(second) \(third)"
        } else if limitedDigits.count >= 3 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3))
            return "\(first) \(second)"
        }
        return limitedDigits
    }
    
    private func formatJapanesePhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 7 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3).prefix(4))
            let third = String(limitedDigits.dropFirst(7))
            return "\(first)-\(second)-\(third)"
        } else if limitedDigits.count >= 3 {
            let first = String(limitedDigits.prefix(3))
            let second = String(limitedDigits.dropFirst(3))
            return "\(first)-\(second)"
        }
        return limitedDigits
    }
    
    private func formatAustralianPhoneNumber(_ digits: String) -> String {
        let limitedDigits = digits
        
        if limitedDigits.count >= 6 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4).prefix(3))
            let third = String(limitedDigits.dropFirst(7))
            return "\(first) \(second) \(third)"
        } else if limitedDigits.count >= 4 {
            let first = String(limitedDigits.prefix(4))
            let second = String(limitedDigits.dropFirst(4))
            return "\(first) \(second)"
        }
        return limitedDigits
    }
    
    private func formatGenericPhoneNumber(_ digits: String) -> String {
        // Generic formatting - just return the digits with spaces every 3-4 characters
        let limitedDigits = digits
        
        if limitedDigits.count > 4 {
            let groups = stride(from: 0, to: limitedDigits.count, by: 3).map { i in
                let start = limitedDigits.index(limitedDigits.startIndex, offsetBy: i)
                let end = limitedDigits.index(start, offsetBy: min(3, limitedDigits.count - i))
                return String(limitedDigits[start..<end])
            }
            return groups.joined(separator: " ")
        }
        return limitedDigits
    }
    
    private func getPlaceholderForCountry(_ countryCode: String) -> String {
        switch countryCode {
        case "US", "CA":
            return "(555) 123-4567"
        case "GB":
            return "7911 123456"
        case "FR":
            return "06 12 34 56 78"
        case "DE":
            return "030 12345678"
        case "JP":
            return "090-1234-5678"
        case "AU":
            return "0412 345 678"
        default:
            return "123 456 789"
        }
    }
    
    private func getMinLengthForCountry(_ countryCode: String) -> Int {
        switch countryCode {
        case "US", "CA": return 10
        case "GB": return 10
        case "FR": return 9
        case "DE": return 10
        case "JP": return 10
        case "AU": return 9
        case "IT", "ES": return 9
        case "NL", "BE": return 9
        case "CH": return 9
        case "AT": return 10
        case "SE", "NO", "DK": return 8
        case "PL": return 9
        case "RU": return 10
        case "TR": return 10
        case "IL": return 9
        case "BR": return 10
        case "MX": return 10
        case "AR": return 10
        case "CL": return 9
        case "CO": return 10
        case "PE": return 9
        case "IN": return 10
        case "CN": return 11
        case "KR": return 10
        case "TH": return 9
        case "VN": return 9
        case "SG": return 8
        case "MY": return 9
        case "ID": return 10
        case "PH": return 10
        case "NZ": return 9
        case "ZA": return 9
        case "EG": return 10
        case "NG": return 10
        case "KE": return 9
        default: return 8
        }
    }
    
    private func getMaxLengthForCountry(_ countryCode: String) -> Int {
        switch countryCode {
        case "US", "CA": return 10
        case "GB": return 11
        case "FR": return 10
        case "DE": return 12
        case "JP": return 11
        case "AU": return 10
        case "IT": return 10
        case "ES": return 9
        case "NL", "BE": return 9
        case "CH": return 10
        case "AT": return 13
        case "SE": return 10
        case "NO", "DK": return 8
        case "PL": return 9
        case "RU": return 10
        case "TR": return 10
        case "IL": return 10
        case "BR": return 11
        case "MX": return 10
        case "AR": return 11
        case "CL": return 9
        case "CO": return 10
        case "PE": return 9
        case "IN": return 10
        case "CN": return 11
        case "KR": return 11
        case "TH": return 10
        case "VN": return 11
        case "SG": return 8
        case "MY": return 11
        case "ID": return 13
        case "PH": return 10
        case "NZ": return 10
        case "ZA": return 10
        case "EG": return 10
        case "NG": return 11
        case "KE": return 10
        default: return 15
        }
    }
    
    private func getFullPhoneNumber() -> String {
        let digitsOnly = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return selectedCountry.dialCode + digitsOnly
    }
    
    // MARK: - Computed Properties for UI States
    private var phoneValidationColor: Color {
        if !hasInteracted { return Color.white.opacity(0.6) }
        return phoneIsValid ? Color.green.opacity(0.8) : Color.red.opacity(0.8)
    }
    
    private var buttonBackgroundColor: LinearGradient {
        return LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 64/255, green: 156/255, blue: 255/255), // #409CFF
                Color(red: 100/255, green: 180/255, blue: 255/255) // #64B4FF
            ]),
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    private var buttonOpacity: Double {
        if isLoading { return 0.8 }
        return (isFormValid && agreesToTerms || !hasInteracted) ? 1.0 : 0.6
    }
    
    // MARK: - Send Verification Code Method
    private func sendVerificationCode() {
        // Prevent double submission
        guard !isLoading else { return }
        
        // Final validation before submission
        guard isFormValid else {
            errorMessage = "Please enter a valid phone number"
            showingError = true
            return
        }
        
        guard agreesToTerms else {
            errorMessage = "Please agree to the Terms & Conditions to continue."
            showingError = true
            return
        }
        
        isLoading = true
        
        Task {
            do {
                let fullPhoneNumber = getFullPhoneNumber()
                try await authService.sendPhoneVerificationCode(phoneNumber: fullPhoneNumber)
                
                await MainActor.run {
                    // Add success haptic feedback
                    let successFeedback = UINotificationFeedbackGenerator()
                    successFeedback.notificationOccurred(.success)
                    
                    showingPhoneVerification = true
                    isLoading = false
                }
            } catch let error as AuthError {
                await MainActor.run {
                    // Add error haptic feedback
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    
                    errorMessage = error.message
                    showingError = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    let errorFeedback = UINotificationFeedbackGenerator()
                    errorFeedback.notificationOccurred(.error)
                    
                    errorMessage = "An unexpected error occurred: \(error.localizedDescription)"
                    showingError = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Country Code Extension
extension CountryCode {
    static let defaultCountry = CountryCode(name: "United States", code: "US", flag: "🇺🇸", dialCode: "+1")
    
    static let allCountries: [CountryCode] = [
        CountryCode(name: "United States", code: "US", flag: "🇺🇸", dialCode: "+1"),
        CountryCode(name: "Canada", code: "CA", flag: "🇨🇦", dialCode: "+1"),
        CountryCode(name: "United Kingdom", code: "GB", flag: "🇬🇧", dialCode: "+44"),
        CountryCode(name: "Australia", code: "AU", flag: "🇦🇺", dialCode: "+61"),
        CountryCode(name: "Germany", code: "DE", flag: "🇩🇪", dialCode: "+49"),
        CountryCode(name: "France", code: "FR", flag: "🇫🇷", dialCode: "+33"),
        CountryCode(name: "Japan", code: "JP", flag: "🇯🇵", dialCode: "+81"),
        CountryCode(name: "South Korea", code: "KR", flag: "🇰🇷", dialCode: "+82"),
        CountryCode(name: "China", code: "CN", flag: "🇨🇳", dialCode: "+86"),
        CountryCode(name: "India", code: "IN", flag: "🇮🇳", dialCode: "+91"),
        CountryCode(name: "Brazil", code: "BR", flag: "🇧🇷", dialCode: "+55"),
        CountryCode(name: "Mexico", code: "MX", flag: "🇲🇽", dialCode: "+52"),
        CountryCode(name: "Spain", code: "ES", flag: "🇪🇸", dialCode: "+34"),
        CountryCode(name: "Italy", code: "IT", flag: "🇮🇹", dialCode: "+39"),
        CountryCode(name: "Netherlands", code: "NL", flag: "🇳🇱", dialCode: "+31"),
        CountryCode(name: "Sweden", code: "SE", flag: "🇸🇪", dialCode: "+46"),
        CountryCode(name: "Norway", code: "NO", flag: "🇳🇴", dialCode: "+47"),
        CountryCode(name: "Denmark", code: "DK", flag: "🇩🇰", dialCode: "+45"),
        CountryCode(name: "Switzerland", code: "CH", flag: "🇨🇭", dialCode: "+41"),
        CountryCode(name: "Austria", code: "AT", flag: "🇦🇹", dialCode: "+43"),
        CountryCode(name: "Belgium", code: "BE", flag: "🇧🇪", dialCode: "+32"),
        CountryCode(name: "Poland", code: "PL", flag: "🇵🇱", dialCode: "+48"),
        CountryCode(name: "Russia", code: "RU", flag: "🇷🇺", dialCode: "+7"),
        CountryCode(name: "Turkey", code: "TR", flag: "🇹🇷", dialCode: "+90"),
        CountryCode(name: "Israel", code: "IL", flag: "🇮🇱", dialCode: "+972"),
        CountryCode(name: "South Africa", code: "ZA", flag: "🇿🇦", dialCode: "+27"),
        CountryCode(name: "Egypt", code: "EG", flag: "🇪🇬", dialCode: "+20"),
        CountryCode(name: "Nigeria", code: "NG", flag: "🇳🇬", dialCode: "+234"),
        CountryCode(name: "Kenya", code: "KE", flag: "🇰🇪", dialCode: "+254"),
        CountryCode(name: "Argentina", code: "AR", flag: "🇦🇷", dialCode: "+54"),
        CountryCode(name: "Chile", code: "CL", flag: "🇨🇱", dialCode: "+56"),
        CountryCode(name: "Colombia", code: "CO", flag: "🇨🇴", dialCode: "+57"),
        CountryCode(name: "Peru", code: "PE", flag: "🇵🇪", dialCode: "+51"),
        CountryCode(name: "Thailand", code: "TH", flag: "🇹🇭", dialCode: "+66"),
        CountryCode(name: "Vietnam", code: "VN", flag: "🇻🇳", dialCode: "+84"),
        CountryCode(name: "Singapore", code: "SG", flag: "🇸🇬", dialCode: "+65"),
        CountryCode(name: "Malaysia", code: "MY", flag: "🇲🇾", dialCode: "+60"),
        CountryCode(name: "Indonesia", code: "ID", flag: "🇮🇩", dialCode: "+62"),
        CountryCode(name: "Philippines", code: "PH", flag: "🇵🇭", dialCode: "+63"),
        CountryCode(name: "New Zealand", code: "NZ", flag: "🇳🇿", dialCode: "+64")
    ]
}

// MARK: - Country Picker View
struct CountryPickerView: View {
    @Binding var selectedCountry: CountryCode
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    
    private var filteredCountries: [CountryCode] {
        if searchText.isEmpty {
            return CountryCode.allCountries
        } else {
            return CountryCode.allCountries.filter { country in
                country.name.localizedCaseInsensitiveContains(searchText) ||
                country.dialCode.contains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                AppBackgroundView()
                    .ignoresSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Search bar
                    CountrySearchBar(text: $searchText)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    // Country list
                    List(filteredCountries, id: \.code) { country in
                        Button(action: {
                            selectedCountry = country
                            dismiss()
                        }) {
                            HStack {
                                Text(country.flag)
                                    .font(.system(size: 24))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(country.name)
                                        .font(.custom("PlusJakartaSans-Medium", size: 16))
                                        .foregroundColor(.white)
                                    Text(country.dialCode)
                                        .font(.custom("PlusJakartaSans-Regular", size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                
                                Spacer()
                                
                                if country.code == selectedCountry.code {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Select Country")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.white)
            )
        }
    }
}

// MARK: - Search Bar Component
struct CountrySearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.6))
            
            TextField("Search countries...", text: $text, prompt: Text("Search countries...").foregroundColor(.white.opacity(0.5)))
                .font(.custom("PlusJakartaSans-Regular", size: 16))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
    }
}



