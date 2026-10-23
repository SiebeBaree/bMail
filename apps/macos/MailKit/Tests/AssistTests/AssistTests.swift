import Foundation
import MailCore
import Testing

@testable import Assist

@Suite struct AIClientTests {
    private func json(_ provider: AIProvider, model: String = "m", reasoning: Reasoning) throws -> [String: Any] {
        let request = AIRequest(model: model, reasoning: reasoning, system: "rules", prompt: "draft", maxTokens: 100, timeout: 10)
        let data = try AIClient(provider: provider, key: "k").body(for: request)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func anthropicTurnsThinkingOffOrSetsEffort() throws {
        let off = try json(.anthropic, reasoning: .off)
        #expect((off["thinking"] as? [String: String]) == ["type": "disabled"])
        #expect(off["output_config"] == nil)
        #expect(off["max_tokens"] as? Int == 100)
        let system = try #require((off["system"] as? [[String: Any]])?.first)
        #expect(system["text"] as? String == "rules")
        #expect((system["cache_control"] as? [String: String]) == ["type": "ephemeral"])

        let xhigh = try json(.anthropic, reasoning: .xhigh)
        #expect((xhigh["thinking"] as? [String: String]) == ["type": "adaptive"])
        #expect((xhigh["output_config"] as? [String: String]) == ["effort": "xhigh"])
        #expect(xhigh["max_tokens"] as? Int ?? 0 > 100)
    }

    @Test func eachClaudeModelTurnsThinkingOffItsOwnWay() throws {
        let sonnet = try json(.anthropic, model: "claude-sonnet-5-5", reasoning: .off)
        #expect((sonnet["thinking"] as? [String: String]) == ["type": "between_tools"])
        #expect(sonnet["output_config"] == nil)
        let opus = try json(.anthropic, model: "claude-opus-5-5", reasoning: .off)
        #expect((opus["thinking"] as? [String: String]) == ["type": "adaptive"])
        #expect((opus["output_config"] as? [String: String]) == ["effort": "low"])
    }

    @Test func openAIUsesReasoningEffortAndTheGatewaysAReasoningObject() throws {
        let openAI = try json(.openAI, reasoning: .off)
        #expect(openAI["reasoning_effort"] as? String == "none")
        #expect(openAI["max_completion_tokens"] as? Int == 100)
        #expect(openAI["reasoning"] == nil)
        #expect((openAI["messages"] as? [[String: String]])?.first == ["role": "system", "content": "rules"])

        let gateway = try json(.openRouter, reasoning: .xhigh)
        #expect((gateway["reasoning"] as? [String: String]) == ["effort": "xhigh"])
        #expect(gateway["reasoning_effort"] == nil)
        #expect(gateway["max_tokens"] != nil)
    }

    @Test func eachProviderSaysHowHardToThinkItsOwnWay() throws {
        let deepSeekOff = try json(.deepSeek, reasoning: .off)
        #expect((deepSeekOff["thinking"] as? [String: String]) == ["type": "disabled"])
        #expect(deepSeekOff["reasoning_effort"] == nil)
        let deepSeekMax = try json(.deepSeek, reasoning: .max)
        #expect((deepSeekMax["thinking"] as? [String: String]) == ["type": "enabled"])
        #expect(deepSeekMax["reasoning_effort"] as? String == "max")

        let gemini = try json(.google, reasoning: .auto)
        #expect(gemini["reasoning_effort"] == nil && gemini["thinking"] == nil && gemini["reasoning"] == nil)
        #expect(try json(.mistral, reasoning: .off)["reasoning_effort"] as? String == "none")
    }

    @Test func everyProviderDefaultsToReasoningItCanExpress() {
        for provider in AIProvider.allCases {
            #expect(provider.reasoningLevels.contains(provider.defaultReasoning(fast: true)))
            #expect(provider.reasoningLevels.contains(provider.defaultReasoning(fast: false)))
        }
        #expect(AIProvider.anthropic.defaultReasoning(fast: false) == .xhigh)
        #expect(AIProvider.anthropic.defaultReasoning(fast: true) == .off)
    }

    @Test func readsTheAnswerAndTheProvidersError() async throws {
        let session = StubProtocol.session { request in
            if request.url?.path().hasSuffix("/messages") == true {
                (200, #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":" tomorrow."}]}"#)
            } else {
                (401, #"{"error":{"message":"Incorrect API key provided."}}"#)
            }
        }
        let request = AIRequest(model: "m", reasoning: .off, system: "", prompt: "", maxTokens: 10, timeout: 5)
        #expect(try await AIClient(provider: .anthropic, key: "k", session: session).complete(request) == " tomorrow.")
        await #expect(throws: AIError.self) {
            try await AIClient(provider: .openAI, key: "k", session: session).complete(request)
        }
    }
}

@Suite struct LogoTests {
    @Test func aModelShowsItsMakersMark() {
        #expect(Logo.of(model: "anthropic/claude-haiku-5.5", on: .openRouter) == .claude)
        #expect(Logo.of(model: "claude-haiku-5-5", on: .anthropic) == .claude)
        #expect(Logo.of(model: "openai/gpt-oss-120b", on: .groq) == .openAI)
        #expect(Logo.of(model: "z-ai/glm-5.2", on: .vercel) == .zAI)
        #expect(Logo.of(model: "something-new", on: .mistral) == .mistral)
    }
}

@Suite struct CompletionPromptTests {
    @Test func dropsTheQuotedMessageAndTheLineThatIntroducesIt() {
        let text = "Works for me, see you Friday.\n\nOn 21 Oct 2026, Ada Okafor <ada@okafor.studio> wrote:\n> Friday at 10?\n> Ada"
        #expect(ownWords(of: text) == "Works for me, see you Friday.")
        #expect(ownWords(of: "Here it is.\n\n---------- Forwarded message ---------\nFrom: x") == "Here it is.")
    }

    @Test func aSuggestionIsOneLineWithoutTheDraftItRepeats() {
        #expect(CompletionPrompt.suggestion(from: "rough draft is ready.\n\nBest,\nSiebe", before: "The rou", after: "") == "rough draft is ready.")
        #expect(CompletionPrompt.suggestion(from: "Thanks for the deck. I'll", before: "Hi Ada,\n\nThanks for the deck.", after: "") == " I'll")
        #expect(CompletionPrompt.suggestion(from: "I'll send it", before: "Done.", after: "") == " I'll send it")
        #expect(CompletionPrompt.suggestion(from: "  Sounds good", before: "Hi Ada,\n", after: "") == "Sounds good")
    }

    @Test func nothingIsBetterThanSomethingAlreadyThere() {
        #expect(CompletionPrompt.suggestion(from: "", before: "Hi", after: "") == nil)
        #expect(CompletionPrompt.suggestion(from: "\nBest, Siebe", before: "See you then.", after: "") == nil)
        #expect(CompletionPrompt.suggestion(from: " Siebe", before: "Best,\n", after: "Siebe") == nil)
    }

    @Test func examplesPreferMailToTheSamePeople() {
        let ada = Address(name: "Ada", email: "ada@okafor.studio")
        let kai = Address(name: "Kai", email: "kai@fund.vc")
        let old = sent(to: ada, "Thanks Ada, the new deck reads much better.", daysAgo: 30)
        let recent = sent(to: kai, "Kai, the Q3 numbers are attached as promised.", daysAgo: 1)
        let tooShort = sent(to: ada, "Ok!", daysAgo: 0)
        #expect(CompletionPrompt.examples(from: [recent, old, tooShort], to: [ada]).map(\.id) == [old.id, recent.id])
    }

    private func sent(to: Address, _ text: String, daysAgo: Double) -> Message {
        Message(
            id: UUID(), conversationID: UUID(), accountID: UUID(), direction: .outbound, deliveryStatus: nil,
            messageIDHeader: nil, from: Address(email: "siebe@baree.be"), to: [to], cc: [], bcc: [], replyTo: [],
            subject: "Hi", html: nil, text: text, snippet: text, sentAt: Date(timeIntervalSinceNow: -daysAgo * 86_400),
            trackingEnabled: false, attachments: [], links: []
        )
    }
}

@Suite struct LabelPromptTests {
    let receipts = LabelGuide(label: MailLabel(id: UUID(), name: "Receipts", description: "Invoices"), examples: [], corrections: [])
    let investors = LabelGuide(label: MailLabel(id: UUID(), name: "Investors", description: "From investors"), examples: [], corrections: [])

    @Test func picksOnlyLabelsThatExist() {
        let answer = "- receipts\n\"Investors\"\nSpam"
        #expect(LabelPrompt.labels(in: answer, from: [receipts, investors]) == [receipts.label.id, investors.label.id])
        #expect(LabelPrompt.labels(in: "NONE", from: [receipts, investors]).isEmpty)
    }

    @Test func listsWhatItLearnedUnderEachLabel() {
        var guide = receipts
        guide.corrections = [.init(from: "Kiln", subject: "Your trial ends in 3 days", snippet: "Upgrade now")]
        let system = LabelPrompt.system([guide])
        #expect(system.contains("<label name=\"Receipts\">\nInvoices\nThe user took it off these"))
        #expect(system.contains("From Kiln, \"Your trial ends in 3 days\""))
    }
}

/// Answers every request with what `respond` returns, so the client runs against canned provider responses.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var respond: @Sendable (URLRequest) -> (Int, String) = { _ in (500, "") }

    static func session(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> URLSession {
        Self.respond = respond
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
