import SwiftUI

/// The bMail mark: a paper plane of two triangles, its fold in gray, on a black squircle. Black in both appearances,
/// like the app icon, so it reads as the brand rather than a control.
public struct LogoMark: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(RadialGradient(colors: [Color(white: 0.11), .black], center: .top, startRadius: 0, endRadius: size))
            PlaneShape(\.wing).fill(.white)
            PlaneShape(\.fold).fill(Color(white: 0.56))
        }
        .frame(width: size, height: size)
        .accessibilityLabel("bMail")
    }
}

/// The mark and the name side by side, where the first launch's intro lands. `isDots` is the version the intro samples:
/// the plane without its squircle and the name in white, laid out exactly like the real one.
public struct Wordmark: View {
    private let size: CGFloat
    private let isDots: Bool

    public init(size: CGFloat) {
        self.init(size: size, isDots: false)
    }

    init(size: CGFloat, isDots: Bool) {
        self.size = size
        self.isDots = isDots
    }

    public var body: some View {
        HStack(spacing: size * 0.34) {
            if isDots {
                ZStack {
                    PlaneShape(\.wing).fill(.white)
                    PlaneShape(\.fold).fill(Color(white: 0.56))
                }
                .frame(width: size, height: size)
            } else {
                LogoMark(size: size)
            }
            Text("bMail")
                .font(.geist(size * 0.66, .semibold))
                .tracking(-size * 0.02)
                .foregroundStyle(isDots ? Color.white : Color.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("bMail")
    }
}

/// The plane on a 100 by 100 grid. App/Resources/AppIcon.icon draws the same triangles at 1024.
struct PlaneShape: Shape {
    struct Triangles {
        let wing: [CGPoint] = [CGPoint(x: 18, y: 50), CGPoint(x: 82, y: 22), CGPoint(x: 60, y: 80)]
        let fold: [CGPoint] = [CGPoint(x: 60, y: 80), CGPoint(x: 48, y: 56), CGPoint(x: 82, y: 22)]
    }

    let points: [CGPoint]

    init(_ triangle: KeyPath<Triangles, [CGPoint]>) {
        points = Triangles()[keyPath: triangle]
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines(points.map { CGPoint(x: rect.minX + $0.x / 100 * rect.width, y: rect.minY + $0.y / 100 * rect.height) })
            path.closeSubpath()
        }
    }
}
