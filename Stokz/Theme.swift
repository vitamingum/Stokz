import SwiftUI

/// App Theme - LIQUID DEATH STYLE - Bold Black & White
struct Theme {
    // MARK: - Primary Colors (B&W Liquid Death)
    /// Pure white accent for high contrast
    static let accent = Color.white
    
    /// Secondary accent - pure black
    static let secondary = Color.black
    
    // MARK: - Background Colors
    static let backgroundPrimary = Color.black // Pure black
    static let backgroundSecondary = Color(white: 0.08) // Near black
    static let backgroundCard = Color(white: 0.12) // Dark gray cards
    
    // MARK: - Semantic Colors (B&W style - muted)
    static let positive = Color(white: 0.9) // Light for gains
    static let negative = Color(white: 0.4) // Darker for losses
    
    // MARK: - Text Colors
    static let textPrimary = Color.white
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.4)
    
    // MARK: - Gradients (Subtle B&W)
    static let accentGradient = LinearGradient(
        colors: [Color.white, Color(white: 0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cardGradient = LinearGradient(
        colors: [Color(white: 0.15), Color(white: 0.08)],
        startPoint: .top,
        endPoint: .bottom
    )
    
    static let darkGradient = LinearGradient(
        colors: [Color(white: 0.1), Color.black],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // MARK: - Typography
    static let titleFont = Font.system(size: 32, weight: .black, design: .default)
    static let headlineFont = Font.system(size: 20, weight: .heavy, design: .default)
    static let bodyFont = Font.system(size: 16, weight: .semibold, design: .default)
    static let captionFont = Font.system(size: 12, weight: .bold, design: .default)
}

// MARK: - View Modifiers
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.backgroundCard)
            .cornerRadius(0) // Sharp edges - Liquid Death style
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

struct BoldCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.black)
            .cornerRadius(0)
            .overlay(
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
            )
    }
}

struct GlassStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.black.opacity(0.9))
            .cornerRadius(0)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }
    
    func boldCardStyle() -> some View {
        modifier(BoldCardStyle())
    }
    
    func glassStyle() -> some View {
        modifier(GlassStyle())
    }
}

// MARK: - Custom Button Styles (Liquid Death - Bold & Angular)
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .black))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.white)
            .cornerRadius(0) // Sharp edges
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .black))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.black)
            .cornerRadius(0)
            .overlay(
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .black))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(white: 0.2))
            .cornerRadius(0)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DestructiveButtonStyle {
    static var destructive: DestructiveButtonStyle { DestructiveButtonStyle() }
}
