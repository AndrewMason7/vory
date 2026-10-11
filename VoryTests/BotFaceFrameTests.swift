import SwiftUI
import Testing
@testable import Vory

/// Drawing a bot from a motion frame (1.5, #304): every symbol renders something of the bot's
/// colour, the dark marks inside the lens and the warning read against their light panel in
/// dark mode too (item 4), and a symbol mid-change stays inside the square.
@MainActor @Suite struct BotFaceFrameTests {
    private func render(_ spec: BotLookSpec, frame: BotMotionFrame, size: CGFloat = 64, dark: Bool = false) -> CGImage? {
        let view = Canvas(opaque: false, rendersAsynchronously: false) { ctx, sz in
            BotFace.drawFrame(spec, in: &ctx, size: sz, frame: frame, light: !dark)
        }
        .frame(width: size, height: size)
        .background(dark ? Color.black : Color.white)
        let r = ImageRenderer(content: view)
        r.scale = 2
        return r.cgImage
    }

    private func pixel(_ img: CGImage, x: CGFloat, y: CGFloat) -> (r: Double, g: Double, b: Double)? {
        guard let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return nil }
        let px = Int(x * CGFloat(img.width)), py = Int(y * CGFloat(img.height))
        guard px >= 0, py >= 0, px < img.width, py < img.height else { return nil }
        let i = py * img.bytesPerRow + px * 4
        return (Double(p[i]) / 255, Double(p[i + 1]) / 255, Double(p[i + 2]) / 255)
    }
    private func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }

    private func frame(for state: BotFace.State) -> BotMotionFrame {
        let m = BotMotionModel(seed: 1)
        m.snap(to: .targets(for: state), at: 0)
        return m.advance(to: 0, targets: .targets(for: state))
    }

    @Test func everyStateDrawsTheBotsColour() throws {
        let spec = BotLookSpec(shape: "blob", eyes: "classic", hex: "#3B7BFF")
        for state in [BotFace.State.idle, .thinking, .searching, .usingTool, .streaming, .awaitingApproval, .error, .reconnecting, .listening] {
            let img = try #require(render(spec, frame: frame(for: state)))
            // Somewhere in the square the bot's blue is there.
            var blue = 0
            for y in stride(from: 0.1, to: 0.9, by: 0.05) { for x in stride(from: 0.1, to: 0.9, by: 0.05) {
                if let c = pixel(img, x: x, y: y), c.b > 0.6, c.r < 0.5 { blue += 1 }
            } }
            #expect(blue > 3, "\(state) drew no blue")
        }
    }

    @Test func theDarkMarksReadInDarkMode() throws {
        // The warning's exclamation and the lens's eyes sit on a light panel: against it they
        // are at least 3:1, on white and on black alike (item 4, decision 1).
        let spec = BotLookSpec(shape: "circle", eyes: "classic", hex: "#1C1C1E")
        for dark in [false, true] {
            let warn = try #require(render(spec, frame: frame(for: .error), size: 100, dark: dark))
            let mark = try #require(pixel(warn, x: 0.5, y: 0.5)), panel = try #require(pixel(warn, x: 0.5, y: 0.33))
            let ratio = (max(luminance(mark), luminance(panel)) + 0.05) / (min(luminance(mark), luminance(panel)) + 0.05)
            #expect(ratio >= 3, "the warning mark reads \(ratio):1 against its panel (dark \(dark))")
            let lens = try #require(render(spec, frame: frame(for: .searching), size: 100, dark: dark))
            let eye = try #require(pixel(lens, x: 0.46 - 0.09, y: 0.44)), glass = try #require(pixel(lens, x: 0.46, y: 0.30))
            let r2 = (max(luminance(eye), luminance(glass)) + 0.05) / (min(luminance(eye), luminance(glass)) + 0.05)
            #expect(r2 >= 3, "the lens's eye reads \(r2):1 against the glass (dark \(dark))")
        }
    }

    @Test func aChangeMidWayStaysInTheSquare() throws {
        let spec = BotLookSpec(shape: "cloud", eyes: "classic", hex: "#3B7BFF")
        let m = BotMotionModel(seed: 1)
        m.snap(to: .targets(for: .idle), at: 0)
        var t = 0.0
        for _ in 0..<8 { t += 1 / 60; _ = m.advance(to: t, targets: .targets(for: .streaming)) }
        let f = m.advance(to: t + 1 / 60, targets: .targets(for: .streaming))
        let img = try #require(render(spec, frame: f, size: 64))
        // The outermost pixel rows and columns are empty: nothing was drawn off the square.
        for i in stride(from: 0.0, to: 1.0, by: 0.1) {
            for (x, y) in [(i, 0.005), (i, 0.995), (0.005, i), (0.995, i)] {
                if let c = pixel(img, x: x, y: y) { #expect(c.r > 0.95 && c.g > 0.95 && c.b > 0.95, "ink at the edge (\(x), \(y))") }
            }
        }
    }
}
