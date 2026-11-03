import SwiftUI
import UIKit

/// The REZKA look's colours on the TV, following the system's light or dark appearance.
enum Brand {
    /// Cards and panels.
    static let panel = adaptive(light: UIColor(white: 0, alpha: 0.06), dark: UIColor(white: 1, alpha: 0.07))
    /// A panel or row with focus on it.
    static let focused = adaptive(light: UIColor(white: 0, alpha: 0.14), dark: UIColor(white: 1, alpha: 0.18))
    static let stroke = adaptive(light: UIColor(white: 0, alpha: 0.1), dark: UIColor(white: 1, alpha: 0.1))
    /// Ratings and gold stamps: the system yellow on dark, a deeper gold that stays readable on light.
    static let gold = adaptive(light: UIColor(red: 196 / 255, green: 134 / 255, blue: 0, alpha: 1), dark: .systemYellow)

    static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// A panel nothing in which takes focus, made focusable itself so the remote can scroll down to it
/// and past it; it brightens a little while focused.
private struct FocusPanel: ViewModifier {
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isFocused ? Brand.focused : Brand.panel, in: RoundedRectangle(cornerRadius: 30))
            .scaleEffect(isFocused ? 1.01 : 1)
            .focusable()
            .focused($isFocused)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

extension View {
    /// A panel whose own buttons or links take the focus.
    func panel() -> some View {
        padding(36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.panel, in: RoundedRectangle(cornerRadius: 30))
    }

    /// A panel with nothing focusable in it, which takes the focus itself.
    func focusPanel() -> some View {
        modifier(FocusPanel())
    }
}

/// A row in a panel: no platter of its own, a soft highlight under the focus.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    private struct Row: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(isFocused ? Brand.focused : .clear, in: RoundedRectangle(cornerRadius: 20))
                .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.03 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
