import SwiftUI

/// A dotted envelope that sways, swings its flap open and lets a letter rise out, for while mail is on its way. Dots
/// nearer the eye are bigger and brighter, in the text color. It always starts closed, and with Reduce Motion it holds
/// the frame with the letter out. Under 60 points it draws fewer, bigger dots.
public struct EnvelopeLoader: View {
    private let size: CGFloat
    @State private var start = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        Group {
            if reduceMotion {
                envelope(at: 2.6)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
                    envelope(at: timeline.date.timeIntervalSince(start))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func envelope(at time: Double) -> some View {
        Canvas { context, canvas in
            for dot in Envelope.dots(at: time, side: canvas.width) {
                context.opacity = dot.opacity
                let rect = CGRect(x: dot.x - dot.radius, y: dot.y - dot.radius, width: dot.radius * 2, height: dot.radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(.textPrimary))
            }
        }
    }
}

extension View {
    /// Mirrors `isBusy` into `isShown` for an `EnvelopeLoader`: only once the work has run for a moment, so quick work
    /// shows nothing, and then for long enough that the envelope opens before it goes.
    public func loaderVisibility(while isBusy: Bool, isShown: Binding<Bool>) -> some View {
        modifier(LoaderVisibility(isBusy: isBusy, isShown: isShown))
    }
}

private struct LoaderVisibility: ViewModifier {
    let isBusy: Bool
    @Binding var isShown: Bool
    @State private var shownAt: Date?

    func body(content: Content) -> some View {
        content.task(id: isBusy) {
            let shownFor = shownAt.map { Date.now.timeIntervalSince($0) } ?? .infinity
            try? await Task.sleep(for: .seconds(isBusy ? 0.4 : max(0, 1.6 - shownFor)))
            guard !Task.isCancelled else { return }
            shownAt = isBusy ? .now : nil
            withAnimation(.enter) { isShown = isBusy }
        }
    }
}

/// The envelope at any moment of its 4.8 second loop. It's 1.5 wide and 0.94 tall around the origin with y up, the
/// letter is 1.24 by 0.84 and the flap reaches 0.6 down from its hinge on the top edge.
enum Envelope {
    struct Dot {
        var x: Double
        var y: Double
        var z: Double
        var radius: Double
        var opacity: Double
    }

    static func dots(at t: Double, side: Double) -> [Dot] {
        let isSmall = side < 60
        // Tuned at 200 points. Smaller sizes shrink the dots less, so they stay legible.
        let radiusScale = (side / 200).squareRoot() * (isSmall ? 1.3 : 1)
        let step = isSmall ? 0.15 : 0.052
        let u = t.truncatingRemainder(dividingBy: 4.8)
        let open = easeInOut(span(u, 0.45, 1.15)) * (1 - easeInOut(span(u, 4.05, 4.65)))
        let rise = easeOut(span(u, 1, 2.05)) * (1 - easeInOut(span(u, 3.3, 4.05)))
        let scale = side * (isSmall ? 0.5 : 0.47)
        // Drops as it opens, so the open flap and the letter stay in frame.
        let project = Projection(
            yaw: sin(t * 0.65) * 0.42, tilt: 0.2 + 0.08 * sin(t * 0.45 + 1),
            center: (side / 2, side / 2 + lerp(0.02, 0.27, open) * scale), scale: scale
        )
        let (left, right, bottom, top) = (-0.75, 0.75, -0.47, 0.47)
        var dots: [Dot] = []

        func put(_ x: Double, _ y: Double, _ z: Double, ink: Double = 1, alpha: Double = 1, boost: Double = 0) {
            let point = project(x, y, z)
            let depth = clamp((point.z + 0.8) / 1.6)
            let radius = max(0.4, (0.6 + 1.25 * depth + boost) * radiusScale)
            dots.append(Dot(x: point.x, y: point.y, z: point.z, radius: radius, opacity: (0.2 + 0.8 * (0.28 + 0.72 * depth) * ink) * alpha))
        }

        func line(_ a: (Double, Double, Double), _ b: (Double, Double, Double), ink: Double = 1) {
            let length = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1) + (b.2 - a.2) * (b.2 - a.2)).squareRoot()
            let count = max(1, Int((length / step).rounded()))
            for i in 0...count {
                let f = Double(i) / Double(count)
                put(lerp(a.0, b.0, f), lerp(a.1, b.1, f), lerp(a.2, b.2, f), ink: ink)
            }
        }

        // The body, a faint far face and the folds along the bottom.
        line((left, bottom, 0), (right, bottom, 0))
        line((right, bottom, 0), (right, top, 0))
        line((right, top, 0), (left, top, 0))
        line((left, top, 0), (left, bottom, 0))
        if !isSmall {
            for x in stride(from: left + step * 2, to: right - step, by: step * 1.8) {
                for y in stride(from: bottom + step * 2, to: top - step, by: step * 1.8) {
                    put(x, y, -0.02, ink: 0.5, alpha: 0.45)
                }
            }
        }
        line((left, bottom, 0.015), (0, -0.03, 0.015), ink: 0.85)
        line((right, bottom, 0.015), (0, -0.03, 0.015), ink: 0.85)

        // The letter. Only what has cleared the top edge shows.
        let (width, height) = (1.24, 0.84)
        let base = bottom + 0.07 + rise * 0.62
        let letterZ = -0.005 + rise * 0.08
        func letter(_ x: Double, _ y: Double, ink: Double = 1, boost: Double = 0) {
            if y > top + 0.01 { put(x, y, letterZ, ink: ink, boost: boost) }
        }
        let edgeStep = isSmall ? step : step * 0.9
        for y in stride(from: base, through: base + height, by: edgeStep) {
            letter(-width / 2, y)
            letter(width / 2, y)
        }
        for x in stride(from: -width / 2, through: width / 2 + 1e-6, by: edgeStep) {
            letter(x, base + height)
        }
        let rows: [(drop: Double, length: Double)] =
            isSmall ? [(0.2, 0.55), (0.42, 0.9)] : [(0.16, 0.38), (0.28, 0.95), (0.4, 0.82), (0.52, 0.95), (0.64, 0.58)]
        let indent = -width / 2 + 0.16
        for row in rows {
            for x in stride(from: indent, through: indent + row.length * (width - 0.32), by: step * (isSmall ? 0.8 : 0.7)) {
                letter(x, base + height - row.drop, ink: 0.9, boost: isSmall ? 0.2 : 0.15)
            }
        }

        // The flap turns on its hinge past flat, so the letter rises in front of it.
        let angle = open * .pi * 1.08
        let reach = 0.6
        func flap(_ x: Double, _ d: Double, ink: Double = 1, alpha: Double = 1) {
            put(x, top - d * cos(angle), 0.02 + d * sin(angle), ink: ink, alpha: alpha)
        }
        let edgeCount = Int(((right * right + reach * reach).squareRoot() / step).rounded())
        for i in 0...edgeCount {
            let f = Double(i) / Double(edgeCount)
            flap(lerp(left, 0, f), f * reach)
            flap(lerp(right, 0, f), f * reach)
        }
        if !isSmall {
            for d in stride(from: step * 1.8, to: reach - step, by: step * 1.8) {
                let half = right * (1 - d / reach) - step
                for x in stride(from: -half, through: half, by: step * 1.8) {
                    flap(x, d, ink: 0.5, alpha: 0.45)
                }
            }
        }

        // Far to near, so nearer dots paint over the ones behind them.
        return dots.sorted { $0.z < $1.z }
    }
}

/// Turns around the vertical axis, tilts toward the viewer and flattens. `z` grows toward the viewer.
private struct Projection {
    private let sinYaw: Double, cosYaw: Double, sinTilt: Double, cosTilt: Double
    private let center: (x: Double, y: Double)
    private let scale: Double

    init(yaw: Double, tilt: Double, center: (x: Double, y: Double), scale: Double) {
        sinYaw = sin(yaw)
        cosYaw = cos(yaw)
        sinTilt = sin(tilt)
        cosTilt = cos(tilt)
        self.center = center
        self.scale = scale
    }

    func callAsFunction(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        let turnedX = x * cosYaw + z * sinYaw
        let turnedZ = -x * sinYaw + z * cosYaw
        let tiltedY = y * cosTilt - turnedZ * sinTilt
        return (center.x + turnedX * scale, center.y - tiltedY * scale, y * sinTilt + turnedZ * cosTilt)
    }
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
private func span(_ t: Double, _ from: Double, _ to: Double) -> Double { clamp((t - from) / (to - from)) }
private func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }
private func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

private func easeInOut(_ x: Double) -> Double {
    x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}
