import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// The real marks of AI providers and model makers, from LobeHub's icon set (lobehub/lobe-icons, MIT). One-color marks
/// are drawn in the text color, so they work on light and dark.
public enum Logo: String, CaseIterable, Sendable {
    case anthropic, claude, gemini, deepSeek = "deepseek", kimi, mistral, meta, qwen, groq
    case openAI = "openai", openRouter = "openrouter", vercel, xAI = "xai", zAI = "zai", moonshot

    var isMonochrome: Bool {
        switch self {
        case .anthropic, .openAI, .openRouter, .vercel, .xAI, .zAI, .moonshot, .groq: true
        case .claude, .gemini, .deepSeek, .kimi, .mistral, .meta, .qwen: false
        }
    }

    /// The mark of whoever made a model, from its id: `anthropic/claude-haiku-5.5` on a gateway, `claude-haiku-5-5`
    /// on Anthropic itself. Falls back to the provider's own mark.
    public static func of(model id: String, on provider: AIProvider) -> Logo {
        let id = id.lowercased()
        let marks: [(words: [String], logo: Logo)] = [
            (["anthropic", "claude"], .claude), (["openai", "gpt", "o1", "o3", "o4"], .openAI), (["google", "gemini", "gemma"], .gemini),
            (["x-ai", "xai", "grok"], .xAI), (["deepseek"], .deepSeek), (["z-ai", "zai", "glm", "zhipu"], .zAI),
            (["moonshot", "kimi"], .kimi), (["mistral", "magistral", "codestral", "devstral"], .mistral),
            (["meta", "llama"], .meta), (["qwen"], .qwen),
        ]
        return marks.first { mark in mark.words.contains { id.hasPrefix($0) } }?.logo ?? provider.logo
    }

    /// Decoded once per mark.
    @MainActor private static var cache: [Logo: Image] = [:]

    @MainActor public var image: Image {
        if let cached = Self.cache[self] { return cached }
        let url = Bundle.module.url(forResource: rawValue, withExtension: "png")
        #if os(macOS)
            let image = url.flatMap(NSImage.init(contentsOf:)).map { Image(nsImage: $0) } ?? Image(systemName: "sparkle")
        #else
            let image = url.flatMap { UIImage(contentsOfFile: $0.path) }.map { Image(uiImage: $0) } ?? Image(systemName: "sparkle")
        #endif
        let rendered = image.renderingMode(isMonochrome ? .template : .original)
        Self.cache[self] = rendered
        return rendered
    }
}

/// A provider's or a model maker's mark, at icon size.
public struct LogoView: View {
    private let logo: Logo
    private let size: CGFloat

    public init(_ logo: Logo, size: CGFloat = 14) {
        self.logo = logo
        self.size = size
    }

    public var body: some View {
        logo.image
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
