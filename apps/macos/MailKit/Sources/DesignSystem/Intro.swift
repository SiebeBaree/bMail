import SwiftUI

/// The site's intro, on a first launch: dots blow in from the left, settle into "bMail", hold, then burst and regroup
/// as the wordmark at `landing`, where the real one sits underneath and takes over. A click, tap or key ends it early
/// and Reduce Motion skips it. It draws for about 3.5 seconds and then never again.
///
/// Every dot's position is a function of time. The site leaves trails by only partly clearing its canvas, but Canvas
/// starts each frame blank, so here each moving dot gets a streak back to where it was a moment earlier.
public struct Intro: View {
    private let landing: CGRect
    private let wordmarkSize: CGFloat
    private let finish: () -> Void
    @State private var field: DotField?
    @State private var start = Date.now
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    /// `landing` is the global frame of a `Wordmark(size: wordmarkSize)` under the intro. `finish` runs at the end or on
    /// a skip; fade the intro out from there.
    public init(landing: CGRect, wordmarkSize: CGFloat, finish: @escaping () -> Void) {
        self.landing = landing
        self.wordmarkSize = wordmarkSize
        self.finish = finish
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: field == nil)) { timeline in
                Canvas { context, _ in
                    field?.draw(at: timeline.date.timeIntervalSince(start) * 1000, in: &context)
                }
            }
            .onChange(of: landing, initial: true) { play(in: proxy.size, origin: proxy.frame(in: .global).origin) }
            // The landing spot moved with the window, so the dots would land in the wrong place.
            .onChange(of: proxy.size) { if field != nil { finish() } }
        }
        .background(.black)
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture(perform: finish)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress { _ in
            finish()
            return .handled
        }
        .onAppear { isFocused = true }
        .task(id: field == nil) {
            // Ends on its own once the dots have landed, and after a few seconds if they never got going.
            try? await Task.sleep(for: .milliseconds(field == nil ? 7000 : DotField.end))
            if !Task.isCancelled { finish() }
        }
        .accessibilityHidden(true)
    }

    /// Works out the dots once the wordmark has a place on screen.
    private func play(in size: CGSize, origin: CGPoint) {
        if reduceMotion { return finish() }
        guard field == nil, landing != .zero else { return }
        field = DotField(size: size, landing: landing.offsetBy(dx: -origin.x, dy: -origin.y), wordmarkSize: wordmarkSize, scale: displayScale)
        if field == nil { return finish() }
        start = .now
    }
}

/// The dots, worked out once, and where each one is at any moment. Timings are in milliseconds, the same as the site's.
private struct DotField {
    static let hold = 2150.0
    static let travel = 1150.0
    static let end = Int(hold + 220 + travel)
    static let streak = 36.0

    struct Dot {
        /// Off the left edge, where it blows in from.
        var start: CGPoint
        var word: CGPoint
        var landing: CGPoint
        /// Bend of the path from the word to the wordmark, so the word bursts outward before it regroups.
        var bend: CGPoint
        var isGray: Bool
        var delay: Double
        var gather: Double
        var leave: Double
        var amplitude: Double
        var phase: Double
        var frequency: Double
    }

    let dots: [Dot]
    let wordDot: CGFloat
    let landingDot: CGFloat
    /// The site's motion is sized for a desktop browser; a phone gets less of it.
    let reach: CGFloat

    /// Nil when there's nothing to draw, e.g. without the fonts.
    @MainActor
    init?(size: CGSize, landing: CGRect, wordmarkSize: CGFloat, scale: CGFloat) {
        let fontSize = min(size.width * 0.25, size.height * 0.36, 320)
        let step = min(7, max(3, fontSize / 58))
        let word = Self.sample(Text("bMail").font(.geist(fontSize, .semibold)).tracking(-0.045 * fontSize).foregroundStyle(.white), scale: 1 / step)
        let mark = Self.sample(Wordmark(size: wordmarkSize, isDots: true), scale: scale)
        guard let first = word.points.first, let last = word.points.last, !mark.points.isEmpty else { return nil }

        let wordOrigin = CGPoint(x: (size.width - word.size.width) / 2, y: size.height * 0.46 - word.size.height / 2)
        let center = CGPoint(x: size.width / 2, y: size.height * 0.46)
        let reach = min(1, size.width / 900)
        let spanX = max(1, last.x - first.x)
        let count = max(word.points.count, mark.points.count)
        dots = (0..<count).map { index in
            // Both lists run left to right, so mapping by rank keeps neighbours together on the way up.
            let w = word.points[index * word.points.count / count]
            let m = mark.points[index * mark.points.count / count]
            let target = CGPoint(x: wordOrigin.x + w.x, y: wordOrigin.y + w.y)
            let out = CGPoint(x: target.x - center.x, y: target.y - center.y)
            let length = max(1, hypot(out.x, out.y))
            let burst = (120 + .random(in: 0..<260)) * reach
            return Dot(
                start: CGPoint(x: -40 - .random(in: 0..<1) * size.width * 0.55, y: target.y + (.random(in: 0..<1) - 0.5) * size.height * 0.7),
                word: target,
                landing: CGPoint(x: landing.minX + m.x, y: landing.minY + m.y),
                bend: CGPoint(
                    x: target.x + out.x / length * burst + (60 + .random(in: 0..<180)) * reach,
                    y: target.y + out.y / length * burst - (40 + .random(in: 0..<120)) * reach
                ),
                isGray: m.isGray,
                delay: (w.x - first.x) / spanX * 420 + .random(in: 0..<220),
                gather: 900 + .random(in: 0..<420),
                leave: .random(in: 0..<220),
                amplitude: (20 + .random(in: 0..<70)) * reach,
                phase: .random(in: 0..<(2 * .pi)),
                frequency: 3 + .random(in: 0..<6)
            )
        }
        wordDot = max(1.4, step * 0.46)
        landingDot = 1.15 / scale
        self.reach = reach
    }

    func draw(at t: Double, in context: inout GraphicsContext) {
        var light = Path()
        var gray = Path()
        var streaks = Path()
        for dot in dots {
            guard let now = position(of: dot, at: t) else { continue }
            if let then = position(of: dot, at: t - Self.streak), hypot(now.point.x - then.point.x, now.point.y - then.point.y) > now.size {
                streaks.move(to: then.point)
                streaks.addLine(to: now.point)
            }
            let rect = CGRect(x: now.point.x - now.size / 2, y: now.point.y - now.size / 2, width: now.size, height: now.size)
            // Squares below a point and a half: nobody can tell, and they're cheaper.
            if now.isGray { add(rect, to: &gray) } else { add(rect, to: &light) }
        }
        context.stroke(
            streaks, with: .color(.white.opacity(0.22)),
            style: StrokeStyle(lineWidth: t > Self.hold ? max(0.8, wordDot * 0.5) : wordDot * 0.8, lineCap: .round)
        )
        context.fill(light, with: .color(.white))
        context.fill(gray, with: .color(Color(white: 0.56)))
    }

    private func add(_ rect: CGRect, to path: inout Path) {
        if rect.width < 1.6 { path.addRect(rect) } else { path.addEllipse(in: rect) }
    }

    private func position(of dot: Dot, at t: Double) -> (point: CGPoint, size: CGFloat, isGray: Bool)? {
        if t <= Self.hold {
            let p = min(1, max(0, (t - dot.delay) / dot.gather))
            guard p > 0 else { return nil }
            let e = 1 - pow(1 - p, 3)
            let wind = pow(1 - e, 1.5)
            let x = dot.start.x + (dot.word.x - dot.start.x) * e + cos(dot.phase + p * dot.frequency) * dot.amplitude * 0.35 * wind
            // One shared wave across the field, so the dots travel in gusts rather than as noise.
            let y = dot.start.y + (dot.word.y - dot.start.y) * e + sin(dot.phase + p * dot.frequency) * dot.amplitude * wind
                + sin(x * 0.006 - t * 0.005 + dot.word.y * 0.012) * 110 * reach * wind
            return (CGPoint(x: x, y: y), wordDot, false)
        }
        let p = min(1, max(0, (t - Self.hold - dot.leave) / Self.travel))
        let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
        let a = (1 - e) * (1 - e)
        let b = 2 * (1 - e) * e
        let c = e * e
        let flutter = sin(.pi * e) * 26 * reach * sin(dot.phase + e * 8)
        let x = a * dot.word.x + b * dot.bend.x + c * dot.landing.x + flutter
        let y = a * dot.word.y + b * dot.bend.y + c * dot.landing.y + flutter * 0.6
        return (CGPoint(x: x, y: y), wordDot + (landingDot - wordDot) * e, dot.isGray && e > 0.6)
    }

    struct Sample {
        var x: CGFloat
        var y: CGFloat
        var isGray: Bool
    }

    /// Every covered pixel of `content` drawn at `scale`, column by column from the left, in points from its top left.
    /// A scale below 1 gives the coarse dots of the big word; the display's scale gives the fine dots of the wordmark.
    @MainActor
    static func sample(_ content: some View, scale: CGFloat) -> (points: [Sample], size: CGSize) {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return ([], .zero) }
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return ([], .zero) }
        var points: [Sample] = []
        for column in 0..<width {
            for row in 0..<height {
                let index = (row * width + column) * 4
                let alpha = Int(pixels[index + 3])
                guard alpha >= 128 else { continue }
                points.append(Sample(
                    x: (CGFloat(column) + 0.5) / scale,
                    y: (CGFloat(row) + 0.5) / scale,
                    // Premultiplied, so the plane's fold reads as gray at any coverage.
                    isGray: Int(pixels[index]) * 255 / alpha < 200
                ))
            }
        }
        return (points, CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale))
    }
}
