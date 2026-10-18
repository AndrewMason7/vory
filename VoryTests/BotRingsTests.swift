import SwiftUI
import Testing
@testable import Vory

/// The body's change of shape (1.5, #304): rings that pair up without twisting, a mix that
/// stays inside the square at every step, and ends that are the exact shapes.
@Suite struct BotRingsTests {
    let shapes = BotLookSpec.shapes
    let visuals: [BotVisual] = [.orb, .lens, .toolbox, .warn, .exclaim, .bolt, .bubbles]

    @Test func everyRingHasItsPointsAndStaysInTheSquare() {
        let box = CGRect(x: 0, y: 0, width: 64, height: 64)
        for shape in shapes {
            let r = BotRings.restRing(BotLookSpec(shape: shape, eyes: "classic", hex: "#000000"), size: 64)
            #expect(r.count == BotRings.steps)
            #expect(r.allSatisfy { box.insetBy(dx: -1, dy: -1).contains($0) }, "\(shape)'s rest ring leaves the square")
        }
        for v in visuals {
            let r = BotRings.symbolRing(v, size: 64)
            #expect(r.count == BotRings.steps)
            #expect(r.allSatisfy { box.insetBy(dx: -1, dy: -1).contains($0) }, "\(v)'s ring leaves the square")
            // A ring is not degenerate: its points spread over a good part of the square.
            let xs = r.map(\.x), ys = r.map(\.y)
            #expect((xs.max()! - xs.min()!) > 12 && (ys.max()! - ys.min()!) > 12, "\(v)'s ring collapsed")
        }
    }

    @Test func noPointJumpsFarBetweenMixSteps() {
        // From every shape to every symbol, in steps of 0.1: a ring point moves at most a
        // tenth of the square per step, and the path stays inside the square.
        let size: CGFloat = 100
        let box = CGRect(x: 0, y: 0, width: size, height: size)
        for shape in shapes { for v in visuals {
            let spec = BotLookSpec(shape: shape, eyes: "classic", hex: "#000000")
            let a = BotRings.restRing(spec, size: size), b = BotRings.symbolRing(v, size: size)
            for i in 0..<10 {
                let p0 = BotRings.mixed(a, b, amount: Double(i) / 10), p1 = BotRings.mixed(a, b, amount: Double(i + 1) / 10)
                let b0 = p0.boundingRect, b1 = p1.boundingRect
                #expect(box.insetBy(dx: -1, dy: -1).contains(b1), "\(shape) → \(v) at \(i + 1)/10 leaves the square: \(b1)")
                #expect(abs(b1.midX - b0.midX) < size * 0.1 && abs(b1.midY - b0.midY) < size * 0.1, "\(shape) → \(v): the body jumped between \(i)/10 and \(i + 1)/10")
            }
        } }
    }

    @Test func theEndsAreTheExactShapes() {
        let box = CGRect(x: 5, y: 7, width: 80, height: 80)
        let spec = BotLookSpec(shape: "cloud", eyes: "classic", hex: "#000000")
        #expect(BotRings.body(spec, toward: .orb, amount: 0, in: box).boundingRect == BotFace.bodyPath("cloud", in: box, time: 0, active: false, phase: 0).boundingRect)
        #expect(BotRings.body(spec, toward: .orb, amount: 1, in: box).boundingRect == BotSymbols.path(.orb, in: box).boundingRect)
        let mid = BotRings.body(spec, toward: .orb, amount: 0.5, in: box).boundingRect
        #expect(box.insetBy(dx: -1, dy: -1).contains(mid))
    }
}
