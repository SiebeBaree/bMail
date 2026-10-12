import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Vercel's palette as semantic tokens. Every color has a dark and a light value and follows the window's appearance,
/// so views never check the color scheme themselves.
extension Color {
    /// The reading surface: list and reader.
    public static let canvas = adaptive(dark: 0x0A0A0A, light: 0xFFFFFF)
    /// Window chrome: the top bar, sidebars and settings navigation.
    public static let chrome = adaptive(dark: 0x000000, light: 0xFAFAFA)
    public static let raised = adaptive(dark: 0x111111, light: 0xFFFFFF)
    public static let hover = adaptive(dark: 0x141414, light: 0xF5F5F5)
    public static let selected = adaptive(dark: 0x1A1A1A, light: 0xEBEBEB)
    public static let line = adaptive(dark: 0x1F1F1F, light: 0xEBEBEB)
    public static let lineStrong = adaptive(dark: 0x2E2E2E, light: 0xD4D4D4)

    public static let textPrimary = adaptive(dark: 0xEDEDED, light: 0x171717)
    public static let textSecondary = adaptive(dark: 0xA1A1A1, light: 0x5E5E5E)
    public static let textMuted = adaptive(dark: 0x8F8F8F, light: 0x8F8F8F)
    public static let textFaint = adaptive(dark: 0x6F6F6F, light: 0xA8A8A8)

    public static let accent = adaptive(dark: 0x0A72EF, light: 0x006BFF)
    public static let link = adaptive(dark: 0x52A8FF, light: 0x0068D6)
    public static let success = adaptive(dark: 0x45A557, light: 0x2E9E48)
    public static let warning = adaptive(dark: 0xF5A623, light: 0xD98E04)
    public static let danger = adaptive(dark: 0xE5484D, light: 0xDC3B40)

    /// The primary button: white on dark, near-black on light.
    public static let inverted = adaptive(dark: 0xEDEDED, light: 0x171717)
    public static let onInverted = adaptive(dark: 0x0A0A0A, light: 0xFFFFFF)

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        #if os(macOS)
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
            })
        #else
            Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
            })
        #endif
    }
}

#if os(macOS)
    extension NSColor {
        convenience init(hex: UInt32) {
            self.init(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
#else
    extension UIColor {
        convenience init(hex: UInt32) {
            self.init(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
#endif

/// Spacing, radii and motion. A 4 point grid; radius grows with the size of the thing.
public enum Metrics {
    public static let keyCapRadius: CGFloat = 4
    public static let controlRadius: CGFloat = 6
    public static let popoverRadius: CGFloat = 8
    public static let windowRadius: CGFloat = 12
    public static let controlHeight: CGFloat = 30
}

extension Animation {
    /// Things that appear: palette, menus, toasts. Selection and navigation never animate.
    public static let enter = Animation.spring(duration: 0.18, bounce: 0.08)
}
