import SwiftUI

// Define the font
extension Font {
    // Basic styles
    static let plusJakartaRegular = Font.custom("PlusJakartaSans-Regular", size: 16)
    static let plusJakartaMedium = Font.custom("PlusJakartaSans-Medium", size: 16)
    static let plusJakartaSemibold = Font.custom("PlusJakartaSans-SemiBold", size: 16)
    static let plusJakartaBold = Font.custom("PlusJakartaSans-Bold", size: 16)
    
    // Title styles
    static let plusJakartaLargeTitle = Font.custom("PlusJakartaSans-Bold", size: 34)
    static let plusJakartaTitle = Font.custom("PlusJakartaSans-Bold", size: 28)
    static let plusJakartaTitle2 = Font.custom("PlusJakartaSans-Bold", size: 22)
    static let plusJakartaTitle3 = Font.custom("PlusJakartaSans-SemiBold", size: 20)
    
    // Body styles
    static let plusJakartaBody = Font.custom("PlusJakartaSans-Regular", size: 16)
    static let plusJakartaBodyBold = Font.custom("PlusJakartaSans-SemiBold", size: 16)
    static let plusJakartaCaption = Font.custom("PlusJakartaSans-Regular", size: 14)
    
    // Create a function that returns the font with dynamic size for accessibility
    static func plusJakarta(_ style: TextStyle, weight: Font.Weight = .regular) -> Font {
        let weightString: String
        
        switch weight {
        case .bold:
            weightString = "Bold"
        case .semibold:
            weightString = "SemiBold"
        case .medium:
            weightString = "Medium"
        default:
            weightString = "Regular"
        }
        
        return Font.custom("PlusJakartaSans-\(weightString)", size: UIFont.preferredFont(forTextStyle: style.uiTextStyle).pointSize)
    }
}

// Helper extension to convert SwiftUI TextStyle to UIKit textStyle
extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle:
            return .largeTitle
        case .title:
            return .title1
        case .title2:
            return .title2
        case .title3:
            return .title3
        case .headline:
            return .headline
        case .subheadline:
            return .subheadline
        case .body:
            return .body
        case .callout:
            return .callout
        case .footnote:
            return .footnote
        case .caption:
            return .caption1
        case .caption2:
            return .caption2
        @unknown default:
            return .body
        }
    }
} 