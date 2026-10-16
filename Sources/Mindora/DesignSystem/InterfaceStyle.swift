import SwiftUI

/// Shared window chrome; document colors remain in MapPalette.
enum InterfaceStyle {
    static let sidebarWidth: CGFloat = 224
    static let inspectorWidth: CGFloat = 320
    static let divider = Color(nsColor: .separatorColor).opacity(0.45)
    static let panel = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .textBackgroundColor)
    static let accent = MapTheme.indigo.color
}

struct QuietIconButton: View {
    let title: String
    let symbol: String
    var isSelected = false
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? InterfaceStyle.accent : Color.secondary)
                .frame(width: 28, height: 28)
                .background(isSelected ? InterfaceStyle.accent.opacity(0.1) : hovered ? Color.primary.opacity(0.05) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
            .onHover { hovered = $0 }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(InterfaceStyle.divider, lineWidth: 0.5))
    }
}

/// Draw the shadow on the row surface, keeping text crisp and the hit area stable.
private struct SidebarHoverFeedback: ViewModifier {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovered ? InterfaceStyle.surface : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(tint.opacity(hovered ? 0.07 : 0))
                    }
                    .shadow(color: .black.opacity(hovered ? (colorScheme == .dark ? 0.24 : 0.10) : 0), radius: hovered ? 4 : 0, x: 0, y: hovered ? 2 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(tint.opacity(hovered ? 0.18 : 0), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { hovered = $0 }
            .onDisappear { hovered = false }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
    }
}

extension View {
    func sidebarHoverFeedback(tint: Color = InterfaceStyle.accent) -> some View {
        modifier(SidebarHoverFeedback(tint: tint))
    }
}
