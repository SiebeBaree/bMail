import Foundation

/// One question for a model: a system prompt that stays the same between requests, so providers can cache it, and the
/// part that changes.
public struct AIRequest: Sendable {
    public var model: String
    public var reasoning: Reasoning
    public var system: String
    public var prompt: String
    /// For the answer itself. Thinking gets room of its own on top.
    public var maxTokens: Int
    public var timeout: TimeInterval

    public init(model: String, reasoning: Reasoning, system: String, prompt: String, maxTokens: Int, timeout: TimeInterval) {
        self.model = model
        self.reasoning = reasoning
        self.system = system
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.timeout = timeout
    }
}

/// A model the key can use. The name is the provider's own where it gives one (Anthropic, OpenRouter, Vercel).
public struct AIModel: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?

    public init(id: String, name: String?) {
        self.id = id
        self.name = name
    }

    /// Whether the id or the name contains what was typed.
    public func matches(_ search: String) -> Bool {
        id.localizedCaseInsensitiveContains(search) || (name?.localizedCaseInsensitiveContains(search) ?? false)
    }
}

public struct AIError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// Talks to the provider you picked with your key, straight from this device. Nothing goes through your server.
public struct AIClient: Sendable {
    public let provider: AIProvider
    let key: String
    let session: URLSession

    public init(provider: AIProvider, key: String, session: URLSession = .shared) {
        self.provider = provider
        self.key = key
        self.session = session
    }

    /// The model's answer, as text.
    public func complete(_ request: AIRequest) async throws -> String {
        var urlRequest = authorized(provider == .anthropic ? "messages" : "chat/completions")
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.timeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = try body(for: request)
        let data = try await send(urlRequest)
        if provider == .anthropic {
            let response = try JSONDecoder().decode(MessagesResponse.self, from: data)
            return response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        }
        let response = try JSONDecoder().decode(ChatResponse.self, from: data)
        return response.choices.first?.message.content ?? ""
    }

    /// Every model the key can use.
    public func models() async throws -> [AIModel] {
        let data = try await send(authorized(provider == .anthropic ? "models?limit=1000" : "models"))
        return try JSONDecoder().decode(ModelList.self, from: data).data
            // Gemini lists its models as `models/gemini-…` but takes the bare id.
            .map { AIModel(id: $0.id.replacingOccurrences(of: "models/", with: ""), name: $0.display_name ?? $0.name) }
            .sorted { $0.id < $1.id }
    }

    /// One tiny request to the model, timed, so Settings can say the key works and how fast the model answers.
    public func check(_ choice: ModelChoice) async throws -> Duration {
        let start = ContinuousClock.now
        _ = try await complete(AIRequest(model: choice.model, reasoning: choice.reasoning, system: "Reply with OK.", prompt: "Ping", maxTokens: 5, timeout: 60))
        return ContinuousClock.now - start
    }

    /// Opens the connection ahead of the first real request, so a suggestion doesn't pay for the TLS handshake.
    public func warmUp() async {
        var request = URLRequest(url: provider.baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        _ = try? await session.data(for: request)
    }

    // MARK: - Requests

    func body(for request: AIRequest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var reasoning = request.reasoning
        if provider == .anthropic {
            // Each Claude model turns thinking off its own way: Sonnet 5.5 takes `between_tools` where the others take
            // `disabled`, and Opus 5.5 and Fable can't, so they think as little as they can. Off only works at effort
            // high or below, which every model's default is.
            var thinking = "disabled"
            if request.model.contains("sonnet-5-5") { thinking = "between_tools" }
            if request.model.contains("opus-5-5") || request.model.contains("fable") || request.model.contains("mythos") {
                if reasoning == .off { reasoning = .low }
            }
            return try encoder.encode(MessagesBody(
                model: request.model,
                max_tokens: request.maxTokens + (reasoning == .off ? 0 : 32_000),
                system: [.init(text: request.system)],
                messages: [.init(role: "user", content: request.prompt)],
                thinking: .init(type: reasoning == .off ? thinking : "adaptive"),
                output_config: reasoning == .off || reasoning == .auto ? nil : .init(effort: reasoning.rawValue)
            ))
        }
        let maxTokens = request.maxTokens + (reasoning == .off ? 0 : 32_000)
        var body = ChatBody(
            model: request.model,
            messages: [.init(role: "system", content: request.system), .init(role: "user", content: request.prompt)]
        )
        if provider == .openAI { body.max_completion_tokens = maxTokens } else { body.max_tokens = maxTokens }
        // Each provider has its own way to say how hard to think. `.auto` sends nothing and leaves it to the model.
        switch (provider, reasoning) {
        case (_, .auto): break
        case (.openRouter, _), (.vercel, _):
            body.reasoning = .init(effort: reasoning == .off ? "none" : reasoning.rawValue)
        case (.deepSeek, .off), (.zAI, .off), (.moonshot, .off):
            body.thinking = .init(type: "disabled")
        case (.deepSeek, _):
            body.thinking = .init(type: "enabled")
            body.reasoning_effort = reasoning.rawValue
        default:
            body.reasoning_effort = reasoning == .off ? "none" : reasoning.rawValue
        }
        return try encoder.encode(body)
    }

    private func authorized(_ path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "\(provider.baseURL.absoluteString)/\(path)")!)
        if provider == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) else { return data }
        if let failure = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw AIError(message: failure.error.message)
        }
        throw AIError(message: status == 401 ? "\(provider.title) didn't accept the key." : "\(provider.title) answered \(status).")
    }
}

// MARK: - Wire formats

// Property names are the providers' own, so the encoder needs no key mapping.

private struct MessagesBody: Encodable {
    struct System: Encodable {
        var type = "text"
        var text: String
        var cache_control = ["type": "ephemeral"]
    }

    struct Message: Encodable {
        var role: String
        var content: String
    }

    struct Thinking: Encodable { var type: String }
    struct OutputConfig: Encodable { var effort: String }

    var model: String
    var max_tokens: Int
    var system: [System]
    var messages: [Message]
    var thinking: Thinking
    var output_config: OutputConfig?
}

private struct MessagesResponse: Decodable {
    struct Block: Decodable {
        var type: String
        var text: String?
    }

    var content: [Block]
}

private struct ChatBody: Encodable {
    struct Message: Codable {
        var role: String
        var content: String?
    }

    struct ReasoningOptions: Encodable { var effort: String }
    struct Thinking: Encodable { var type: String }

    var model: String
    var messages: [Message]
    var max_completion_tokens: Int?
    var max_tokens: Int?
    var reasoning_effort: String?
    var reasoning: ReasoningOptions?
    var thinking: Thinking?
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable { var message: ChatBody.Message }
    var choices: [Choice]
}

private struct ModelList: Decodable {
    struct Model: Decodable {
        var id: String
        var display_name: String?
        var name: String?
    }

    var data: [Model]
}

private struct ErrorResponse: Decodable {
    struct Detail: Decodable { var message: String }
    var error: Detail
}
