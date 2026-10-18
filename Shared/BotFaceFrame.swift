import SwiftUI

/// Drawing a bot from a `BotMotionFrame` (1.5, #304): the body morphing into the leading symbol
/// through the rings, any other symbol on its way out shrinking in place, the lighter panels and
/// the ink marks, the eyes seated for the symbol and clipped to the body, then the loops that
/// belong to a symbol (the orb's pulse and halo, the bubbles' hop, the bolt's glint, the
/// listening arcs). Everything here is a transform or a fill on paths the rings cache; only a
/// change of shape rebuilds the body path.
extension BotFace {
    /// The orb's pulse: 0.88 to 1.08 over 1.15 s.
    static func orbPulse(_ loopTime: Double) -> CGFloat { 0.98 + 0.10 * CGFloat(sin(loopTime / 1.15 * 2 * .pi)) }

    /// Each bubble's lift, one after another like a typing indicator, as a fraction of the square.
    static func bubbleHop(_ loopTime: Double, index: Int) -> CGFloat {
        let phase = (loopTime * 1.6 - Double(index) * 0.28).truncatingRemainder(dividingBy: 1.2)
        guard phase >= 0, phase < 0.5 else { return 0 }
        return -0.07 * CGFloat(sin(phase / 0.5 * .pi))
    }

    /// Where along the bolt the glint is (0 to 1), with a rest between passes so the wrap never shows.
    static func glintPosition(_ loopTime: Double) -> CGFloat? {
        let phase = loopTime.truncatingRemainder(dividingBy: 1.6)
        guard phase < 0.9 else { return nil }
        return CGFloat(phase / 0.9)
    }

    /// The anchor of the eyes for a shape heading `amount` of the way into `visual`.
    static func eyeSeat(_ spec: BotLookSpec, toward visual: BotVisual?, amount: Double) -> (x: CGFloat, y: CGFloat, spread: CGFloat) {
        let rest = eyeAnchor(spec.shape)
        guard let visual, let seat = BotSymbols.eyeAnchor(visual), amount > 0.001 else { return (0.5, rest.y, rest.spread) }
        let k = CGFloat(min(1, max(0, amount)))
        return (0.5 + (seat.x - 0.5) * k, rest.y + (seat.y - rest.y) * k, rest.spread + (seat.spread - rest.spread) * k)
    }

    /// A still frame for a Live Activity or Dynamic Island phase (decision 6): the orb for
    /// thinking, the toolbox for a tool (the lens when the detail names a search), the bubbles
    /// level for streaming, the warning for an error, the exclamation while an answer waits,
    /// the rest body otherwise. No halo, no glint, no loop: `loopTime` stays 0.
    public static func stillFrame(phase: String, detail: String, attention: Bool) -> BotMotionFrame {
        let state: State
        if attention { state = .awaitingApproval } else {
            switch phase {
            case "thinking", "working": state = .thinking
            case "tool":
                let d = detail.lowercased()
                state = d.contains("search") || d.contains("grep") || d.contains("browser") || d.contains(" web") ? .searching : .usingTool
            case "streaming": state = .streaming
            case "error", "failed": state = .error
            default: state = .idle
            }
        }
        let m = BotMotionModel(seed: 0)
        m.snap(to: .targets(for: state), at: 0)
        var f = m.advance(to: 0, targets: .targets(for: state))
        f.halo = 0; f.loopTime = 0
        return f
    }

    /// Draws `spec` in `size` from `frame`. `light`: a light background. `bodyAndEyes`: false
    /// draws only what sits over a live glass plate (the extra parts, the panels and marks, the
    /// glint, the arcs); the view draws the plate and the eyes as glass itself.
    public static func drawFrame(_ spec: BotLookSpec, in ctx: inout GraphicsContext, size: CGSize, frame f: BotMotionFrame, light: Bool = false, parts: Part = .all, bodyAndEyes: Bool = true) {
        let box = CGRect(origin: .zero, size: size)
        let s = min(size.width, size.height)
        let tint = Color(botHex: spec.hex) ?? Color(red: 0.49, green: 0.36, blue: 1)
        let pale = isLight(spec.hex)
        let leading = f.leading
        let lead = leading.map { f.amount(of: $0) } ?? 0

        // The squash about the base and the orb's pulse are transforms on the whole bot.
        var scaleX = CGFloat(f.sx), scaleY = CGFloat(f.sy)
        if leading == .orb, lead > 0.5 { let p = orbPulse(f.loopTime); scaleX *= p; scaleY *= p }
        if scaleX != 1 || scaleY != 1 {
            ctx.translateBy(x: size.width / 2, y: size.height * 0.96)
            ctx.scaleBy(x: scaleX, y: scaleY)
            ctx.translateBy(x: -size.width / 2, y: -size.height * 0.96)
        }

        // The halo is the view's (`BotHalo`), behind the bot in a layer the square does not clip.

        // The body: the rest silhouette morphing into the leading symbol.
        let body: Path = shapeBlend(spec, {
            guard let leading else { return bodyPath(spec.shape, in: box, time: 0, active: false, phase: 0) }
            if leading == .bubbles {
                // The body becomes the middle bubble; the other two grow beside it.
                return BotRings.body(spec, toward: .bubbles, amount: lead, in: box)
            }
            return BotRings.body(spec, toward: leading, amount: lead, in: box)
        }(), in: box)
        if parts != .eyes {
            if bodyAndEyes { fillBody(body, tint: tint, in: &ctx, box: box, s: s, light: light, dim: f.dim, pale: pale, glass: spec.isGlass) }
            // The parts a symbol is made of beyond the body: the other bubbles, the exclamation's
            // dot, each growing (or shrinking) in place with the symbol's amount.
            if leading == .bubbles {
                for (i, x) in [0.23, 0.77].enumerated() {
                    let hop = bubbleHop(f.loopTime, index: i == 0 ? 0 : 2) * s * CGFloat(lead)
                    let r = 0.12 * s * CGFloat(lead)
                    let c = CGPoint(x: box.minX + CGFloat(x) * s, y: box.minY + 0.5 * s + hop)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(tint.opacity(Double(lead))))
                }
            }
            if leading == .exclaim, lead > 0.001 {
                let d = 0.24 * s * CGFloat(lead)
                let c = CGPoint(x: box.midX, y: box.minY + 0.84 * s)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)), with: .color(tint.opacity(Double(lead))))
            }
            // A symbol on its way out while another comes in: it shrinks about the centre.
            for v in BotVisual.allCases where v != .rest && v != leading {
                let a = f.amount(of: v)
                guard a > 0.001 else { continue }
                var t = CGAffineTransform(translationX: box.midX, y: box.midY).scaledBy(x: CGFloat(a), y: CGFloat(a)).translatedBy(x: -box.midX, y: -box.midY)
                _ = t
                let p = BotSymbols.path(v, in: box).applying(t)
                ctx.fill(p, with: .color(tint.opacity(a * 0.9)))
                t = .identity
            }
            // The lighter panel and the dark mark inside the lens and the warning (decision 1),
            // the toolbox's lid line: at their size once the symbol is mostly there.
            if let leading, lead > 0.5 {
                let k = smooth((lead - 0.5) / 0.5)
                if let inner = BotSymbols.inner(leading, in: box) {
                    ctx.fill(inner, with: .color(Color(red: 0.97, green: 0.97, blue: 0.99).opacity(0.92 * k)))
                }
                if let mark = BotSymbols.ink(leading, in: box) {
                    ctx.fill(mark, with: .color(ink.opacity(0.94 * k)))
                }
                if leading == .bolt, let g = glintPosition(f.loopTime) {
                    // A white glint running along the bolt, tilted with it, clipped to it.
                    ctx.drawLayer { layer in
                        layer.clip(to: BotSymbols.path(.bolt, in: box))
                        let x = box.minX + (g * 1.4 - 0.2) * s
                        layer.fill(Path(box), with: .linearGradient(Gradient(colors: [.white.opacity(0), .white.opacity(0.85 * k), .white.opacity(0)]),
                                                                     startPoint: CGPoint(x: x, y: box.midY + 0.03 * s), endPoint: CGPoint(x: x + 0.12 * s, y: box.midY - 0.03 * s)))
                    }
                }
            }
            if f.dim > 0.01, bodyAndEyes {
                ctx.drawLayer { layer in layer.clip(to: body); layer.fill(Path(box), with: .color(.black.opacity(0.22 * f.dim))) }
            }
        }

        // The eyes: seated for the symbol, blinking, orbiting the body on a finish, clipped to it.
        if parts != .body, bodyAndEyes, f.eyeOpacity > 0.001 {
            let seat = eyeSeat(spec, toward: leading, amount: lead)
            var m = Motion()
            m.eyeOpen = f.eyeOpen
            m.eyeX = f.eyeX; m.eyeY = f.eyeY
            m.freezeGlance = true
            var eyes = eyePaths(spec, size: size, time: 0, active: false, gaze: .zero, motion: m, anchor: seat).path
            if f.orbit > 0 {
                // Round the body once: across the face, hidden on the back, and back in.
                let theta = f.orbit * 2 * .pi
                let slide = CGFloat(sin(theta)) * s * 0.22
                eyes = eyes.applying(CGAffineTransform(translationX: slide, y: 0))
                let visible = smooth((cos(theta) + 0.18) / 0.38)
                if visible < 0.01 { return }
                ctx.drawLayer { layer in
                    layer.opacity = f.eyeOpacity * visible
                    layer.clip(to: body)
                    layer.fill(eyes, with: .color(spec.isGlass ? ink.opacity(0.9) : ink))
                }
                return
            }
            ctx.drawLayer { layer in
                layer.opacity = f.eyeOpacity
                layer.clip(to: body)
                layer.fill(eyes, with: .color(spec.isGlass ? ink.opacity(0.9) : ink))
            }
        }

        // The listening arcs, off the body's sides, in their own layer so they are never clipped.
        if parts != .eyes, f.arcs > 0.01 {
            ctx.stroke(BotSymbols.arcs(in: box, amount: f.arcs), with: .color(tint.opacity(0.7 * f.arcs)), style: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        }
    }

    /// The body's fill: the painted glass or the flat colour with the crown light, as `draw` has them.
    static func fillBody(_ body: Path, tint: Color, in ctx: inout GraphicsContext, box: CGRect, s: CGFloat, light: Bool, dim: Double, pale: Bool, glass: Bool) {
        if glass {
            drawGlassBody(body, tint: tint, in: &ctx, box: box, s: s, light: light, dim: dim, pale: pale)
        } else {
            ctx.fill(body, with: .linearGradient(Gradient(colors: [tint.opacity(1), tint.opacity(0.84)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: box.height)))
            ctx.drawLayer { layer in
                layer.clip(to: body)
                let crown: Color = pale ? Color(red: 0.72, green: 0.76, blue: 0.86).opacity(0.5 * (1 - dim)) : .white.opacity(0.22 * (1 - dim))
                layer.fill(Path(box), with: .linearGradient(Gradient(colors: [crown, crown.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: box.height * 0.55)))
            }
        }
        if pale { drawInnerStroke(body, in: &ctx, s: s) }
    }
}

/// The body as a Shape from a frame, for live glass: the rest silhouette morphing into the
/// symbol the frame leads with. `inset` > 0 gives the rim mask (each piece toward its centre).
public struct BotFrameShape: Shape {
    public var spec: BotLookSpec
    public var visual: BotVisual?
    public var amount: Double
    public var inset: CGFloat = 0
    public init(spec: BotLookSpec, visual: BotVisual?, amount: Double, inset: CGFloat = 0) {
        self.spec = spec; self.visual = visual; self.amount = amount; self.inset = inset
    }
    public func path(in rect: CGRect) -> Path {
        let p = BotFace.shapeBlend(spec, visual.map { BotRings.body(spec, toward: $0, amount: amount, in: rect) } ?? BotFace.bodyPath(spec.shape, in: rect, time: 0, active: false, phase: 0), in: rect)
        return inset > 0 ? BotFace.rimInner(p, inset: inset) : p
    }
}

/// The orb's halo (1.5): a soft round glow in the bot's colour, 1.5 times the bot across, that
/// breathes with the pulse and fades to nothing. A view of its own behind the bot, so the bot's
/// square never clips it (item 11); nothing below 32 pt, where it would be a smudge.
public struct BotHalo: View {
    public var spec: BotLookSpec
    public var size: CGFloat
    public var frame: BotMotionFrame
    public init(spec: BotLookSpec, size: CGFloat, frame: BotMotionFrame) { self.spec = spec; self.size = size; self.frame = frame }
    public var body: some View {
        let tint = Color(botHex: spec.hex) ?? Color(red: 0.49, green: 0.36, blue: 1)
        let lead = frame.amount(of: .orb)
        let glow = 0.28 + 0.55 * (0.5 + 0.5 * sin(frame.loopTime / 1.15 * 2 * .pi))
        let strength = frame.halo * glow * lead
        if size >= 32, strength > 0.01 {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.55 * strength), tint.opacity(0)], center: .center, startRadius: size * 0.34, endRadius: size * 0.76))
                .frame(width: size * 1.52, height: size * 1.52)
                .scaleEffect(BotFace.orbPulse(frame.loopTime))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
