import CoreGraphics

struct CanvasViewport: Equatable {
    static let minimumScale: CGFloat = 0.15
    static let maximumScale: CGFloat = 3
    var scale: CGFloat = 1
    var offset = CGPoint.zero

    func screenPoint(_ world: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: world.x * scale + size.width / 2 + offset.x,
                y: world.y * scale + size.height / 2 + offset.y)
    }
    func worldPoint(_ screen: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: (screen.x - size.width / 2 - offset.x) / scale,
                y: (screen.y - size.height / 2 - offset.y) / scale)
    }
    func screenRect(_ world: CGRect, in size: CGSize) -> CGRect {
        CGRect(origin: screenPoint(world.origin, in: size), size: CGSize(width: world.width * scale, height: world.height * scale))
    }
    mutating func zoom(by factor: CGFloat, at anchor: CGPoint, in size: CGSize) {
        let world = worldPoint(anchor, in: size)
        scale = min(Self.maximumScale, max(Self.minimumScale, scale * factor))
        offset = CGPoint(x: anchor.x - size.width / 2 - world.x * scale,
                         y: anchor.y - size.height / 2 - world.y * scale)
    }
    mutating func fit(_ bounds: CGRect, in size: CGSize) {
        guard !bounds.isNull, size.width > 0, size.height > 0 else { return }
        scale = min(1.5, max(Self.minimumScale, min((size.width - 96) / max(bounds.width, 1), (size.height - 96) / max(bounds.height, 1))))
        offset = CGPoint(x: -bounds.midX * scale, y: -bounds.midY * scale)
    }
}
