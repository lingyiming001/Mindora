import SwiftUI

/// Shared window chrome; document colors remain in MapPalette.
enum InterfaceStyle {
    static let sidebarWidth: CGFloat = 224
    static let inspectorWidth: CGFloat = 340
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
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(InterfaceStyle.divider).frame(height: 0.5) }
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

struct InspectorSwitch: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

struct InspectorChoices<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    var tint: Color = InterfaceStyle.accent
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(label(option)).font(.system(size: 11, weight: selection == option ? .semibold : .regular))
                        .frame(maxWidth: .infinity).frame(height: 27)
                        .foregroundStyle(selection == option ? tint : Color.secondary)
                        .background(selection == option ? InterfaceStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }.padding(3).background(InterfaceStyle.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(title)
    }
}
