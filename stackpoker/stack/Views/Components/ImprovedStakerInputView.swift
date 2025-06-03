import SwiftUI

struct ImprovedStakerInputView: View {
    @Binding var config: StakerConfig
    @ObservedObject var userService: UserService
    
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let glassOpacity: Double
    let materialOpacity: Double
    var onRemove: () -> Void
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with collapse/expand
            headerView
            
            if isExpanded {
                VStack(spacing: 12) {
                    // Staker search field
                    StakerSearchField(
                        config: $config,
                        userService: userService,
                        primaryTextColor: primaryTextColor,
                        secondaryTextColor: secondaryTextColor,
                        glassOpacity: glassOpacity,
                        materialOpacity: materialOpacity
                    )
                    
                    // Only show percentage and markup fields if a staker is selected OR manual entry has a name
                    if (config.selectedStaker != nil) || (config.isManualEntry && !config.manualStakerName.isEmpty) {
                        stakeDetailsFields
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Material.ultraThinMaterial)
                .opacity(materialOpacity * 0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke((config.selectedStaker != nil || (config.isManualEntry && !config.manualStakerName.isEmpty)) ? primaryTextColor.opacity(0.3) : secondaryTextColor.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
    }
    
    @ViewBuilder
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.selectedStaker == nil && !config.isManualEntry ? "New Staker" : "Staker")
                    .font(.plusJakarta(.subheadline, weight: .bold))
                    .foregroundColor(primaryTextColor)
                
                if config.isManualEntry {
                    if config.manualStakerName.isEmpty {
                        Text("Enter staker name above")
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor.opacity(0.7))
                    } else {
                        Text(config.manualStakerName)
                            .font(.plusJakarta(.caption, weight: .medium))
                            .foregroundColor(secondaryTextColor)
                    }
                } else if let selectedStaker = config.selectedStaker {
                    Text("@\(selectedStaker.username)")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                } else {
                    Text("Tap to configure")
                        .font(.plusJakarta(.caption, weight: .medium))
                        .foregroundColor(secondaryTextColor.opacity(0.7))
                }
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Expand/collapse button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(secondaryTextColor.opacity(0.8))
                }
                
                // Remove button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        onRemove()
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
        }
    }
    
    @ViewBuilder
    private var stakeDetailsFields: some View {
        HStack(spacing: 12) {
            // Percentage Sold Field
            GlassyInputField(
                icon: "chart.pie.fill",
                title: "Percentage (%)",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                HStack {
                    TextField("50", text: $config.percentageSold)
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                    
                    Text("%")
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.vertical, 4)
            }
            
            // Markup Field
            GlassyInputField(
                icon: "percent",
                title: "Markup",
                glassOpacity: glassOpacity,
                labelColor: secondaryTextColor,
                materialOpacity: materialOpacity
            ) {
                HStack {
                    TextField("1.1", text: $config.markup)
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(primaryTextColor)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                    
                    Text("x")
                        .font(.plusJakarta(.body, weight: .medium))
                        .foregroundColor(secondaryTextColor)
                }
                .padding(.vertical, 4)
            }
        }
        
        // Helper text for markup
        if !config.markup.isEmpty, let markupValue = Double(config.markup), markupValue > 1.0 {
            let markupPercentage = (markupValue - 1.0) * 100
            Text("Markup: \(markupPercentage, specifier: "%.1f")% above buy-in cost")
                .font(.plusJakarta(.caption2, weight: .medium))
                .foregroundColor(secondaryTextColor.opacity(0.8))
                .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Validation
    
    private var isValid: Bool {
        if config.isManualEntry {
            guard !config.manualStakerName.isEmpty else { return false }
        } else {
            guard config.selectedStaker != nil else { return false }
        }
        guard let percentage = Double(config.percentageSold), percentage > 0, percentage <= 100 else { return false }
        guard let markup = Double(config.markup), markup >= 1.0 else { return false }
        return true
    }
} 