// Draws the app icon into the asset catalog: a black squircle with a white envelope, nothing else.
// Run from apps/macos: swift scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset")

func draw(size: Int) -> Data {
    let scale = CGFloat(size) / 1024
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: scale, y: scale)

        // The macOS icon grid: 824 points of body centered in 1024, with room for the shadow.
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        NSColor.black.setFill()
        squircle.fill()
        context.restoreGState()

        let gradient = NSGradient(starting: NSColor(white: 0.13, alpha: 1), ending: NSColor(white: 0.02, alpha: 1))!
        gradient.draw(in: squircle, angle: -90)
        NSColor(white: 1, alpha: 0.10).setStroke()
        let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
        rim.lineWidth = 4
        rim.stroke()

        let envelope = CGRect(x: 272, y: 352, width: 480, height: 330)
        let outline = NSBezierPath(roundedRect: envelope, xRadius: 44, yRadius: 44)
        outline.lineWidth = 38
        NSColor.white.setStroke()
        outline.stroke()
        let flap = NSBezierPath()
        flap.move(to: CGPoint(x: envelope.minX + 34, y: envelope.maxY - 38))
        flap.line(to: CGPoint(x: envelope.midX, y: envelope.midY - 6))
        flap.line(to: CGPoint(x: envelope.maxX - 34, y: envelope.maxY - 38))
        flap.lineWidth = 38
        flap.lineCapStyle = .round
        flap.lineJoinStyle = .round
        flap.stroke()
        return true
    }
    let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return representation.representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try! draw(size: size).write(to: output.appendingPathComponent("icon_\(size).png"))
}
print("Wrote icons to \(output.path)")
