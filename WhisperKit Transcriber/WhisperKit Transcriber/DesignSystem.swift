
import SwiftUI

// MARK: - Design Theme
struct Theme {
    // Colors - Derived from App Icon (Dark Mode "Cyber-MCM")
    static let background = Color(red: 0.05, green: 0.07, blue: 0.12) // Deep Midnight Blue
    static let surface = Color(red: 0.10, green: 0.13, blue: 0.20) // Darker Blue-Grey Glass
    static let text = Color(red: 0.94, green: 0.96, blue: 1.0) // Cool White
    static let accent = Color(red: 1.0, green: 0.55, blue: 0.1) // Neon Orange (from waves)
    static let secondaryAccent = Color(red: 0.0, green: 0.75, blue: 1.0) // Neon Cyan (from quill/waves)
    static let border = Color.white.opacity(0.1) // Subtle light border

    // Layout
    static let cornerRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 12 // Slightly softer to match the fluid waves
    static let padding: CGFloat = 24
    static let shadowRadius: CGFloat = 8

    // Font
    // We'll use system fonts but with specific weights/designs to mimic generic sans
    static func headerFont() -> Font {
        .system(.title2, design: .default).weight(.bold)
    }

    static func bodyFont() -> Font {
        .system(.body, design: .default)
    }

    static func monoFont() -> Font {
        .system(.caption, design: .monospaced)
    }
}

// MARK: - View Modifiers

struct MCMCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.padding)
            .background(Theme.surface)
            .cornerRadius(Theme.cornerRadius)
            .shadow(color: Color.black.opacity(0.05), radius: Theme.shadowRadius, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .stroke(Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func mcmCard() -> some View {
        self.modifier(MCMCardStyle())
    }
}

// MARK: - Button Styles

struct MCMButtonStyle: ButtonStyle {
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(color)
            .cornerRadius(Theme.buttonRadius)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .shadow(color: color.opacity(0.5), radius: 6, x: 0, y: 0) // External glow style
    }
}

// MARK: - Toggle Styles

struct MCMToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: {
            configuration.isOn.toggle()
        }) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(configuration.isOn ? .white : Theme.text)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 60) // Enforce height for multiline consistency
                .background(configuration.isOn ? Theme.secondaryAccent.opacity(0.3) : Color.white.opacity(0.05))
                .cornerRadius(12) // Softer corners
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(configuration.isOn ? Theme.secondaryAccent : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.1), value: configuration.isOn)
    }
}
