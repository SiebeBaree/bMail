import Foundation

/// Where AI requests go, on your own key. Anthropic speaks its Messages api; the other three speak OpenAI's Chat
/// Completions.
public enum AIProvider: String, CaseIterable, Codable, Sendable {
    case anthropic
    case openAI = "openai"
    case openRouter = "openrouter"
    case vercel

    public var title: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAI: "OpenAI"
        case .openRouter: "OpenRouter"
        case .vercel: "Vercel AI Gateway"
        }
    }

    var baseURL: URL {
        switch self {
        case .anthropic: URL(string: "https://api.anthropic.com/v1")!
        case .openAI: URL(string: "https://api.openai.com/v1")!
        case .openRouter: URL(string: "https://openrouter.ai/api/v1")!
        case .vercel: URL(string: "https://ai-gateway.vercel.sh/v1")!
        }
    }

    /// Where to make a key, linked from Settings.
    public var keysURL: URL {
        switch self {
        case .anthropic: URL(string: "https://platform.claude.com/settings/keys")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .openRouter: URL(string: "https://openrouter.ai/settings/keys")!
        case .vercel: URL(string: "https://vercel.com/docs/ai-gateway/authentication-and-byok")!
        }
    }

    /// Haiku 5.5 everywhere it's served, GPT-6 Luna on OpenAI. The gateways name models `vendor/model`.
    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-haiku-5-5"
        case .openAI: "gpt-6-luna"
        case .openRouter, .vercel: "anthropic/claude-haiku-5.5"
        }
    }
}

/// How long the model thinks before answering. Off is fastest, which is what tab completion needs.
public enum Reasoning: String, CaseIterable, Codable, Sendable {
    case off, low, medium, high, xhigh, max

    public var title: String {
        switch self {
        case .off: "Off"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .xhigh: "xHigh"
        case .max: "Max"
        }
    }
}
