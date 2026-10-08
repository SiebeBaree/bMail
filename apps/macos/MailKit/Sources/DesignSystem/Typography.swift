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
}

extension Typography {
    /// The bundled font files, for web content that runs in its own process and can't see registered fonts.
    public static func fontData(named name: String) -> Data? {
        Bundle.module.url(forResource: name, withExtension: "ttf").flatMap { try? Data(contentsOf: $0) }
    }
}
