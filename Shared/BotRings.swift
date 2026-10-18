import SwiftUI

/// Rings of points for the body's change of shape (1.5, #304): the rest silhouette and each
/// symbol's, sampled on rays from an origin chosen per symbol so every ray meets the outline
/// once, paired point for point and mixed straight into one path. Built once per shape, size
/// and symbol and cached, so a frame mid-change allocates nothing but the path it draws.
public enum BotRings {
    public static let steps = 144

    /// Where the rays start for a symbol, as a fraction of the square: the symbols with a
    /// handle or a tail are star-shaped only from a point away from the centre.
    static func origin(for visual: BotVisual) -> CGPoint {
        switch visual {
        case .lens: CGPoint(x: 0.46, y: 0.46)
        case .toolbox: CGPoint(x: 0.5, y: 0.62)
        case .warn: CGPoint(x: 0.5, y: 0.62)
        case .exclaim: CGPoint(x: 0.5, y: 0.34)
        case .bolt: CGPoint(x: 0.5, y: 0.5)
        case .bubbles: CGPoint(x: 0.5, y: 0.5)
        case .orb, .rest: CGPoint(x: 0.5, y: 0.5)
        }
    }

    /// The outline of `path` as `steps` points on rays from `origin`, clockwise from the top:
    /// march out for the last inside sample, then bisect (a shape that is not star-shaped from
    /// the origin would otherwise catch an inner edge).
    public static func ring(of path: Path, box: CGRect, origin: CGPoint, steps: Int = steps) -> [CGPoint] {
        let c = CGPoint(x: box.minX + origin.x * box.width, y: box.minY + origin.y * box.height)
        let reach = hypot(box.width, box.height)
        let march = 48
        return (0..<steps).map { i in
            let a = Double(i) / Double(steps) * 2 * .pi - .pi / 2
            let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            func inside(_ r: CGFloat) -> Bool { path.contains(CGPoint(x: c.x + dx * r, y: c.y + dy * r)) }
            var lastIn: CGFloat = 0
            for k in 1...march { let r = reach * CGFloat(k) / CGFloat(march); if inside(r) { lastIn = r } }
            var lo = lastIn, hi = min(reach, lastIn + reach / CGFloat(march))
            for _ in 0..<8 { let mid = (lo + hi) / 2; if inside(mid) { lo = mid } else { hi = mid } }
            return CGPoint(x: c.x + dx * lo, y: c.y + dy * lo)
        }
    }

    /// `a` blended `amount` of the way to `b`, as one closed path, with no array in between.
    public static func mixed(_ a: [CGPoint], _ b: [CGPoint], amount: Double) -> Path {
        let k = CGFloat(min(1, max(0, amount)))
        var p = Path()
        let n = min(a.count, b.count)
        guard n > 2 else { return p }
        for i in 0..<n {
            let pt = CGPoint(x: a[i].x + (b[i].x - a[i].x) * k, y: a[i].y + (b[i].y - a[i].y) * k)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    nonisolated(unsafe) private static var cache: [String: [CGPoint]] = [:]
    private static let lock = NSLock()

    /// The rest body's ring for `spec` in a square of `size` (origin zero), cached by shape and size.
    public static func restRing(_ spec: BotLookSpec, size: CGFloat) -> [CGPoint] {
        let key = "rest|\(spec.shape)|\(Int(size.rounded()))"
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit { return hit }
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        let path = BotFace.bodyPath(spec.shape, in: box, time: 0, active: false, phase: 0)
        let ring = self.ring(of: path, box: box, origin: CGPoint(x: 0.5, y: 0.5))
        lock.lock(); cache[key] = ring; lock.unlock()
        return ring
    }

    /// A symbol's silhouette ring in a square of `size` (origin zero), cached by symbol and size.
    /// The bubbles and the exclamation are several pieces; their ring is the first piece's (the
    /// body becomes the middle bubble, the mark's stem), the other pieces grow in place.
    public static func symbolRing(_ visual: BotVisual, size: CGFloat) -> [CGPoint] {
        let key = "sym|\(visual.rawValue)|\(Int(size.rounded()))"
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit { return hit }
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        let path: Path
        switch visual {
        case .bubbles: path = Path(ellipseIn: CGRect(x: 0.38 * size, y: 0.38 * size, width: 0.24 * size, height: 0.24 * size))
        case .exclaim: path = Path(roundedRect: CGRect(x: 0.38 * size, y: 0.06 * size, width: 0.24 * size, height: 0.56 * size), cornerRadius: 0.12 * size, style: .continuous)
        default: path = BotSymbols.path(visual, in: box)
        }
        let ring = self.ring(of: path, box: box, origin: origin(for: visual))
        lock.lock(); cache[key] = ring; lock.unlock()
        return ring
    }

    /// The body mid-change: the rest ring blended toward `visual`'s by `amount`, in `box`.
    public static func body(_ spec: BotLookSpec, toward visual: BotVisual, amount: Double, in box: CGRect) -> Path {
        let size = min(box.width, box.height)
        if visual == .rest || amount <= 0.001 { return BotFace.bodyPath(spec.shape, in: box, time: 0, active: false, phase: 0) }
        if amount >= 0.999 { return BotSymbols.path(visual, in: box) }
        let a = restRing(spec, size: size), b = symbolRing(visual, size: size)
        return mixed(a, b, amount: amount).offsetBy(dx: box.minX, dy: box.minY)
    }
}
