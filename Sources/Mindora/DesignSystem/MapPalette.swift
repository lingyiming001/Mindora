import AppKit
import SwiftUI

extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

extension MapTheme {
    var accent: NSColor {
        switch self {
        case .indigo: NSColor(hex: "6264D9")!
        case .forest: NSColor(hex: "2C8A78")!
        case .sunset: NSColor(hex: "C86B48")!
        case .graphite: NSColor(hex: "657186")!
        }
    }
    var branchColors: [NSColor] {
        switch self {
        case .indigo: ["6264D9", "4D91B8", "A471B0", "4E9A83", "B98C51"].compactMap(NSColor.init(hex:))
        case .forest: ["2C8A78", "6D9560", "4B8EAB", "AB9258", "8B7DA8"].compactMap(NSColor.init(hex:))
        case .sunset: ["C86B48", "B28B42", "AD6981", "7C81B3", "58958B"].compactMap(NSColor.init(hex:))
        case .graphite: ["657186", "788694", "627D87", "8B7E91", "778575"].compactMap(NSColor.init(hex:))
        }
    }
    var color: Color { Color(nsColor: accent) }
}

struct MapPalette {
    let theme: MapTheme
    let dark: Bool
    var canvas: NSColor { NSColor(hex: dark ? "191B22" : "F7F8FC")! }
    var surface: NSColor { NSColor(hex: dark ? "262934" : "FFFFFF")! }
    var text: NSColor { NSColor(hex: dark ? "EEEFF5" : "303444")! }
    var secondary: NSColor { NSColor(hex: dark ? "A2A7B8" : "7A8193")! }
    var grid: NSColor { NSColor(hex: dark ? "30333E" : "E1E4EF")! }
    func branchColor(_ node: MindMapNode, index: Int) -> NSColor {
        node.style?.colorHex.flatMap(NSColor.init(hex:)) ?? theme.branchColors[index % theme.branchColors.count]
    }
}
