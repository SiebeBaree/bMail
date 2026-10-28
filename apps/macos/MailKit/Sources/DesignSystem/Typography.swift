import CoreText
import SwiftUI

/// Geist and Geist Mono ship inside the app. Call `register()` once at launch, before the first view draws.
public enum Typography {
    public static func register() {
        for name in ["Geist-Variable", "GeistMono-Variable"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Font {
    /// Geist at an interface size. 13 for chrome and lists, 14 for reading, 20 for subjects.
    public static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist", fixedSize: size).weight(weight)
    }

    /// Geist Mono for times, counts, addresses in tables and key caps.
    public static func geistMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Geist Mono", fixedSize: size).weight(weight)
    }

    public static let ui = geist(13)
    public static let uiMedium = geist(13, .medium)
    public static let uiSemibold = geist(13, .semibold)
    public static let reading = geist(14)
    public static let pageTitle = geist(20, .semibold)
    public static let meta = geistMono(12)
    public static let keyCap = geistMono(11)

    /// SF Symbols, by where they sit, a step under the text beside them. The leading icon of a palette or menu row.
    public static let rowIcon = Font.system(size: 13)
    /// Beside interface text, in buttons and bars.
    public static let icon = Font.system(size: 12)
    /// Beside 12pt meta text: a row's star, an address, a label.
    public static let smallIcon = Font.system(size: 11)
    /// Chevrons, checkmarks and close marks inside a control.
    public static let controlIcon = Font.system(size: 9, weight: .semibold)
}

extension Typography {
    /// The bundled font files, for web content that runs in its own process and can't see registered fonts.
    public static func fontData(named name: String) -> Data? {
        Bundle.module.url(forResource: name, withExtension: "ttf").flatMap { try? Data(contentsOf: $0) }
    }
}
