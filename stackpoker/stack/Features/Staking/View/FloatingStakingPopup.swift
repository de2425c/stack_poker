import SwiftUI

struct FloatingStakingPopup: View {
    @Binding var isPresented: Bool
    @Binding var stakerConfigs: [StakerConfig]
    @ObservedObject var userService: UserService
    @ObservedObject var manualStakerService: ManualStakerService
    
    let userId: String
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    
    @State private var dragOffset: CGSize = .zero
    @State private var showPopup: Bool = false
    
    var body: some View {
        if isPresented {
            ZStack {
                // Full screen background overlay
                Color.black
                    .opacity(showPopup ? 0.4 : 0)
                    .ignoresSafeArea(.all)
                    .onTapGesture {
                        dismissPopup()
                    }
                
                // Popup content container
                VStack(spacing: 0) {
                    // Main popup card
                    VStack(spacing: 0) {
                        // Scrollable content
                        stakingContent
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.clear)
                            .background(
                                AppBackgroundView()
                                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 25, x: 0, y: 10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(primaryTextColor.opacity(0.15), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.75)
                    .scaleEffect(showPopup ? 1.0 : 0.8)
                    .offset(y: dragOffset.height)
                    .offset(y: showPopup ? 0 : UIScreen.main.bounds.height * 0.3)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height > 0 {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                if value.translation.height > 100 {
                                    dismissPopup()
                                } else {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    ).padding(.horizontal, 24)
                    .padding(.vertical, 60)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.all)
                .onAppear {
                    presentPopup()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
    }
    
    @ViewBuilder
    private var stakingContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Staking Configuration")
                            .font(.plusJakarta(.title2, weight: .bold))
                            .foregroundColor(primaryTextColor)
                        
                        Text("Configure your stakers for this session")
                            .font(.plusJakarta(.subheadline, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    }
                    
                    Spacer()
                    
                    Button(action: dismissPopup) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(secondaryTextColor.opacity(0.8))
                    }
                }
                .padding(.horizontal, 24)
                
                // Staker configurations
                VStack(spacing: 20) {
                    ForEach(Array(stakerConfigs.enumerated()), id: \.element.id) { index, config in
                        ImprovedStakerInputView(
                            config: Binding(
                                get: { 
                                    // Safely get the config if index is still valid
                                    index < stakerConfigs.count ? stakerConfigs[index] : config
                                },
                                set: { newValue in
                                    // Safely set the config if index is still valid
                                    if index < stakerConfigs.count {
                                        stakerConfigs[index] = newValue
                                    }
                                }
                            ),
                            userService: userService,
                            manualStakerService: manualStakerService,
                            userId: userId,
                            primaryTextColor: primaryTextColor,
                            secondaryTextColor: secondaryTextColor,
                            glassOpacity: glassOpacity,
                            materialOpacity: materialOpacity * 0.6,
                            onRemove: {
                                removeStaker(id: config.id)
                            }
                        )
                        .id(config.id)
                        .padding(.horizontal, 24)
                    }
                }
                
                // Add another staker button
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        stakerConfigs.append(StakerConfig())
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                        Text("Add Another Staker")
                    }
                    .font(.plusJakarta(.body, weight: .semibold))
                    .foregroundColor(primaryTextColor)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(primaryTextColor.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .padding(.horizontal, 24)
                
                // Done button
                Button(action: dismissPopup) {
                    Text("Done")
                        .font(.plusJakarta(.body, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .padding(.top, 20)
        }
        .onTapGesture {
            // Dismiss keyboard when tapping on the background
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    private func presentPopup() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            showPopup = true
        }
    }
    
    private func dismissPopup() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showPopup = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            isPresented = false
            dragOffset = .zero
        }
    }
    
    private func removeStaker(id idToRemove: UUID) {
        print("--- Staker Removal Attempt (id path) ---")
        print("[\(Date())] removeStaker called for id: \(idToRemove)")
        
        // Use immediate removal with proper animation
        withAnimation(.easeOut(duration: 0.3)) {
            stakerConfigs.removeAll { $0.id == idToRemove }
        }
        
        print("[\(Date())] After removal, stakerConfigs count: \(stakerConfigs.count), IDs: \(stakerConfigs.map { $0.id })")
        
        // If no stakers left, dismiss the popup
        if stakerConfigs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                dismissPopup()
            }
        }
    }
} 