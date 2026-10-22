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

    /// Every model the key can use, by id.
    public func models() async throws -> [String] {
        let data = try await send(authorized(provider == .anthropic ? "models?limit=1000" : "models"))
        return try JSONDecoder().decode(ModelList.self, from: data).data.map(\.id).sorted()
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
        let thinkingRoom = request.reasoning == .off ? 0 : 32_000
        switch provider {
        case .anthropic:
            return try encoder.encode(MessagesBody(
                model: request.model,
                max_tokens: request.maxTokens + thinkingRoom,
                system: [.init(text: request.system)],
                messages: [.init(role: "user", content: request.prompt)],
                // Haiku 5.5 only turns thinking off at effort high or below, which the default medium is.
                thinking: .init(type: request.reasoning == .off ? "disabled" : "adaptive"),
                output_config: request.reasoning == .off ? nil : .init(effort: request.reasoning.rawValue)
            ))
        case .openAI, .openRouter, .vercel:
            let effort = request.reasoning == .off ? "none" : request.reasoning.rawValue
            let isOpenAI = provider == .openAI
            return try encoder.encode(ChatBody(
                model: request.model,
                messages: [.init(role: "system", content: request.system), .init(role: "user", content: request.prompt)],
                max_completion_tokens: isOpenAI ? request.maxTokens + thinkingRoom : nil,
                max_tokens: isOpenAI ? nil : request.maxTokens + thinkingRoom,
                reasoning_effort: isOpenAI ? effort : nil,
                reasoning: isOpenAI ? nil : .init(effort: effort)
            ))
        }
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

    var model: String
    var messages: [Message]
    var max_completion_tokens: Int?
    var max_tokens: Int?
    var reasoning_effort: String?
    var reasoning: ReasoningOptions?
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable { var message: ChatBody.Message }
    var choices: [Choice]
}

private struct ModelList: Decodable {
    struct Model: Decodable { var id: String }
    var data: [Model]
}

private struct ErrorResponse: Decodable {
    struct Detail: Decodable { var message: String }
    var error: Detail
}
