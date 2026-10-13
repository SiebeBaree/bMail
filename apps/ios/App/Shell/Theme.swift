import SwiftUI
import UIKit

extension Font {
    /// Geist at a phone size that grows with Dynamic Type. 16 reads like the system's 17.
    static func phone(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("Geist", size: size, relativeTo: style).weight(weight)
    }

    /// Geist Mono for times and counts.
    static func phoneMono(_ size: CGFloat, relativeTo style: Font.TextStyle = .footnote) -> Font {
        .custom("Geist Mono", size: size, relativeTo: style)
    }
}

@MainActor
enum Theme {
    /// Navigation titles in Geist like everything else. Runs once, after the fonts are registered and before the first
    /// bar is drawn.
    static func apply() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [
            .font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: geist(32, .bold)),
            .kern: -0.6,
        ]
        bar.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: geist(17, .semibold))]
    }

    static func geist(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [.family: "Geist", .traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// The few moments that deserve a tap in the hand: mail leaving, an action taken back, something that failed. Swipes
/// bring their own.
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func failure() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}
