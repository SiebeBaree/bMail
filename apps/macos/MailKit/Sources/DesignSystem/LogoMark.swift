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

/// The plane on a 100 by 100 grid, shared with the app icon script.
private struct PlaneShape: Shape {
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
