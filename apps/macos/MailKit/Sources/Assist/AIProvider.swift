import Foundation

/// Where AI requests go, on your own key. Anthropic speaks its Messages api; every other provider speaks OpenAI's Chat
/// Completions, each with its own way to set reasoning.
public enum AIProvider: String, CaseIterable, Codable, Sendable {
    case anthropic
    case openAI = "openai"
    case google
    case xAI = "xai"
    case deepSeek = "deepseek"
    case zAI = "zai"
    case moonshot
    case mistral
    case groq
    case openRouter = "openrouter"
    case vercel

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .google: "Google Gemini"
        case .xAI: "xAI"
        case .deepSeek: "DeepSeek"
        case .zAI: "Z.ai (GLM)"
        case .moonshot: "Moonshot (Kimi)"
        case .mistral: "Mistral"
        case .groq: "Groq"
        case .openRouter: "OpenRouter"
        case .vercel: "Vercel AI Gateway"
        }
    }

    public var logo: Logo {
        switch self {
        case .anthropic: .anthropic
        case .openAI: .openAI
        case .google: .gemini
        case .xAI: .xAI
        case .deepSeek: .deepSeek
        case .zAI: .zAI
        case .moonshot: .moonshot
        case .mistral: .mistral
        case .groq: .groq
        case .openRouter: .openRouter
        case .vercel: .vercel
        }
    }

    var baseURL: URL {
        switch self {
        case .anthropic: URL(string: "https://api.anthropic.com/v1")!
        case .openAI: URL(string: "https://api.openai.com/v1")!
        case .google: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        case .xAI: URL(string: "https://api.x.ai/v1")!
        case .deepSeek: URL(string: "https://api.deepseek.com")!
        case .zAI: URL(string: "https://api.z.ai/api/paas/v4")!
        case .moonshot: URL(string: "https://api.moonshot.ai/v1")!
        case .mistral: URL(string: "https://api.mistral.ai/v1")!
        case .groq: URL(string: "https://api.groq.com/openai/v1")!
        case .openRouter: URL(string: "https://openrouter.ai/api/v1")!
        case .vercel: URL(string: "https://ai-gateway.vercel.sh/v1")!
        }
    }

    /// Where to make a key, linked from Settings.
    public var keysURL: URL {
        switch self {
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .google: URL(string: "https://aistudio.google.com/apikey")!
        case .xAI: URL(string: "https://console.x.ai")!
        case .deepSeek: URL(string: "https://platform.deepseek.com/api_keys")!
        case .zAI: URL(string: "https://z.ai/manage-apikey/apikey-list")!
        case .moonshot: URL(string: "https://platform.moonshot.ai/console/api-keys")!
        case .mistral: URL(string: "https://console.mistral.ai/api-keys")!
        case .groq: URL(string: "https://console.groq.com/keys")!
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")!
        case .vercel: URL(string: "https://vercel.com/docs/ai-gateway/authentication-and-byok")!
        }
    }

    /// Haiku 5.5 wherever it's served and GPT-6 Luna on OpenAI. Elsewhere the provider's fast model, or an alias that
    /// follows it. The gateways name models `vendor/model`.
    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-haiku-5-5"
        case .openAI: "gpt-6-luna"
        case .google: "gemini-flash-latest"
        case .xAI: "grok-4.3"
        case .deepSeek: "deepseek-v4-flash"
        case .zAI: "glm-5.2"
        case .moonshot: "kimi-k2.6"
        case .mistral: "mistral-small-latest"
        case .groq: "openai/gpt-oss-120b"
        case .openRouter, .vercel: "anthropic/claude-haiku-5.5"
        }
    }

    /// The reasoning levels the provider's api can express, fastest first. `.auto` leaves it to the model, for
    /// providers that can't turn thinking off or only switch it on and off.
    public var reasoningLevels: [Reasoning] {
        switch self {
        case .anthropic, .openRouter, .vercel: [.off, .low, .medium, .high, .xhigh, .max]
        case .openAI, .xAI: [.off, .low, .medium, .high, .xhigh]
        case .google: [.auto, .low, .medium, .high]
        case .deepSeek: [.off, .high, .max]
        case .zAI, .moonshot: [.off, .auto]
        case .mistral: [.off, .high]
        case .groq: [.auto, .low, .medium, .high]
        }
    }

    /// Completion has to keep up with your typing, so it thinks as little as the provider allows. Labelling runs in the
    /// background and gets it right more often when it thinks: xHigh where there is one.
    public func defaultReasoning(fast: Bool) -> Reasoning {
        let levels = reasoningLevels
        if fast { return levels.contains(.off) ? .off : levels.contains(.low) ? .low : levels[0] }
        return levels.contains(.xhigh) ? .xhigh : levels.last { $0 != .max } ?? levels[0]
    }
}

/// How long the model thinks before answering.
public enum Reasoning: String, CaseIterable, Codable, Sendable {
    case auto, off, low, medium, high, xhigh, max

    public var title: String {
        switch self {
        case .auto: "Default"
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "xHigh"
        case .max: "Max"
        }
    }
}
