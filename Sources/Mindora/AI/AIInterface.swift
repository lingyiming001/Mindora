import SwiftUI

/// Explicit surfaces and field labels keep AI screens independent of macOS Form row styling.
struct AICard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(InterfaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(InterfaceStyle.divider, lineWidth: 1))
    }
}
struct AIField<Content: View>: View {
    let title: String
    let hint: String?
    let content: Content
    @FocusState private var focused: Bool
    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.hint = hint; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
            content.font(.system(size: 13)).textFieldStyle(.plain).labelsHidden().focused($focused)
                .multilineTextAlignment(.leading).padding(.horizontal, 11).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(InterfaceStyle.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? InterfaceStyle.accent.opacity(0.55) : InterfaceStyle.divider, lineWidth: 1))
            if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct AIBadge: View {
    let title: String
    var highlighted = false
    var body: some View {
        Text(title).font(.system(size: 10, weight: .medium))
            .foregroundStyle(highlighted ? InterfaceStyle.accent : .secondary)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(highlighted ? InterfaceStyle.accent.opacity(0.1) : Color.primary.opacity(0.05), in: Capsule())
    }
}
