import SwiftUI

struct StakingPreviewDemoView: View {
    @StateObject private var userService = UserService()
    @State private var stakerConfigs: [StakerConfig] = [StakerConfig()]
    @State private var showStakingSection = true
    
    private let primaryTextColor = Color.white
    private let secondaryTextColor = Color.white.opacity(0.7)
    private let glassOpacity = 0.01
    private let materialOpacity = 0.2
    
    var body: some View {
        ZStack {
            AppBackgroundView().ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    Text("Improved Staking Interface Demo")
                        .font(.plusJakarta(.title, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 50)
                    
                    // Staking Section Toggle
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            withAnimation {
                                showStakingSection.toggle()
                                if showStakingSection && stakerConfigs.isEmpty {
                                    stakerConfigs.append(StakerConfig())
                                }
                            }
                        }) {
                            HStack {
                                Text(showStakingSection ? "Hide Staking Details" : "Add Staking Details")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                Spacer()
                                Image(systemName: showStakingSection ? "chevron.up" : "chevron.down")
                                    .foregroundColor(primaryTextColor)
                            }
                        }
                        .padding(.leading, 6)
                        .padding(.bottom, showStakingSection ? 10 : 0)
                    }
                    .padding(.horizontal)

                    // Staking Details Section (Conditional)
                    if showStakingSection {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Staking Info")
                                    .font(.plusJakarta(.headline, weight: .medium))
                                    .foregroundColor(primaryTextColor)
                                Spacer()
                            }
                            .padding(.leading, 6)
                            .padding(.bottom, 2)

                            ForEach($stakerConfigs) { $configBinding in
                                ImprovedStakerInputView(
                                    config: $configBinding,
                                    userService: userService,
                                    primaryTextColor: primaryTextColor,
                                    secondaryTextColor: secondaryTextColor,
                                    glassOpacity: glassOpacity,
                                    materialOpacity: materialOpacity,
                                    onRemove: {
                                        if let index = stakerConfigs.firstIndex(where: { $0.id == configBinding.id }) {
                                            stakerConfigs.remove(at: index)
                                            if stakerConfigs.isEmpty {
                                                showStakingSection = false
                                            }
                                        }
                                    }
                                )
                            }
                            
                            Button(action: {
                                stakerConfigs.append(StakerConfig())
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Another Staker")
                                }
                                .font(.plusJakarta(.body, weight: .medium))
                                .foregroundColor(primaryTextColor.opacity(0.9))
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                )
                            }
                            .padding(.top, stakerConfigs.isEmpty ? 0 : 10)
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    Spacer(minLength: 100)
                }
            }
        }
        .navigationTitle("Staking Demo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationView {
        StakingPreviewDemoView()
    }
} 