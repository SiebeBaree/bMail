import Foundation
import MailUI
import MCP
import Network
import SQLiteData
import Testing

@testable import Agents
@testable import MailCore

@Suite struct AgentToolsTests {
    let store: MailStore
    let work = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe Baree", domainID: nil, position: 0)
    let personal = Account(id: UUID(), kind: .gmail, address: "siebe@gmail.com", displayName: "Siebe", domainID: nil, position: 1)
    let anna = Address(name: "Anna Peeters", email: "anna@acme.com")

    init() throws {
        store = MailStore(database: try inMemoryDatabase())
        var changes = ChangeSet()
        changes.accounts = [work, personal]
        try store.merge(changes, source: "server")
    }

    @Test func anAccountAtOffDoesntExistForAgents() throws {
        let numbers = try receive("Q3 numbers", on: work)
        let holiday = try receive("Holiday photos", on: personal)
        let tools = tools([work.id: .read])

        #expect(try tools.call("list_conversations", arguments: [:], agent: "Claude").text.contains(numbers.id.uuidString))
        #expect(try !tools.call("list_conversations", arguments: [:], agent: "Claude").text.contains(holiday.id.uuidString))
        #expect(try !tools.call("list_conversations", arguments: ["query": "holiday"], agent: "Claude").text.contains(holiday.id.uuidString))
        #expect(try !tools.call("list_accounts", arguments: [:], agent: "Claude").text.contains(personal.address))
        #expect(throws: AgentError("There's no conversation with id \(holiday.id).")) {
            try tools.call("read_conversation", arguments: ["id": .string(holiday.id.uuidString)], agent: "Claude")
        }
        #expect(throws: AgentError("There's no account \(personal.address).")) {
            try tools.call("send_email", arguments: ["from": .string(personal.address), "to": ["anna@acme.com"], "body": "Hi"], agent: "Claude")
        }
    }

    @Test func readOnlyListsAndAllowsReading() throws {
        let numbers = try receive("Q3 numbers", on: work)
        let tools = tools([work.id: .read])

        #expect(try tools.list().map(\.name) == ["list_accounts", "list_conversations", "read_conversation"])
        #expect(try tools.call("read_conversation", arguments: ["id": .string(numbers.id.uuidString)], agent: "Claude").text.contains("Can you check these?"))
        #expect(throws: AgentError("bMail only lets agents read \(work.address).")) {
            try tools.call("update_conversations", arguments: ["ids": .string(numbers.id.uuidString), "action": "done"], agent: "Claude")
        }
        #expect(throws: AgentError("bMail doesn't let agents send from any account.")) {
            try tools.call("send_email", arguments: ["to": ["anna@acme.com"], "subject": "Hi", "body": "Hi"], agent: "Claude")
        }
    }

    @Test func organizingIsUndoableAndNamesTheAgent() throws {
        let numbers = try receive("Q3 numbers", on: work)
        let result = try tools([work.id: .organize])
            .call("update_conversations", arguments: ["ids": [.string(numbers.id.uuidString)], "action": "done"], agent: "Claude Code")

        guard case let .apply(mutations, toast) = result.effect else { Issue.record("Expected mutations"); return }
        #expect(mutations == [.move(numbers.id, from: .inbox, to: .done)])
        #expect(toast == "Claude Code marked 1 conversation done")
    }

    @Test func askToSendWaitsForYouAndSendGoesOut() throws {
        let numbers = try receive("Q3 numbers", on: work)
        let reply: [String: Value] = ["reply_to": .string(numbers.id.uuidString), "body": "They look right."]

        let asked = try tools([work.id: .askToSend]).call("send_email", arguments: reply, agent: "Claude Code").effect
        guard case let .review(draft) = asked else { Issue.record("Expected a draft to review"); return }
        #expect(draft.to == [anna])
        #expect(draft.subject == "Re: Q3 numbers")
        #expect(draft.conversationID == numbers.id)
        #expect(draft.message.text.hasPrefix("They look right."))
        #expect(draft.message.text.contains("> Can you check these?"))

        let sent = try tools([work.id: .send]).call("send_email", arguments: reply, agent: "Claude Code").effect
        guard case .send = sent else { Issue.record("Expected a send"); return }
    }

    private func tools(_ levels: [Account.ID: AgentAccess]) -> AgentTools {
        AgentTools(store: store) { levels[$0] ?? .off }
    }

    private func receive(_ subject: String, on account: Account) throws -> Conversation {
        let conversation = Conversation(
            id: UUID(), accountID: account.id, subject: subject, folder: .inbox, isRead: false, isStarred: false,
            snoozedUntil: nil, lastMessageAt: .now, lastOutboundAt: nil
        )
        let message = Message(
            id: UUID(), conversationID: conversation.id, accountID: account.id, direction: .inbound, deliveryStatus: nil,
            messageIDHeader: nil, from: anna, to: [Address(email: account.address)], cc: [], bcc: [], replyTo: [], subject: subject,
            html: nil, text: "Can you check these?", snippet: "Can you check these?", sentAt: .now, trackingEnabled: false,
            attachments: [], links: []
        )
        var changes = ChangeSet()
        changes.conversations = [conversation]
        changes.messages = [message]
        try store.merge(changes, source: "server")
        return conversation
    }
}

@Suite struct AgentEndpointTests {
    let store: MailStore
    let work = Account(id: UUID(), kind: .domain, address: "siebe@baree.be", displayName: "Siebe Baree", domainID: nil, position: 0)

    init() throws {
        store = MailStore(database: try inMemoryDatabase())
        var changes = ChangeSet()
        changes.accounts = [work]
        try store.merge(changes, source: "server")
    }

    @Test func withoutTheTokenNothingAnswers() async throws {
        let endpoint = endpoint(effects: Effects())
        #expect(await endpoint.respond(to: post(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#, token: nil)).status == 401)
        #expect(await endpoint.respond(to: post(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#, token: "wrong")).status == 401)
    }

    @Test func anAgentConnectsAndActsUnderItsOwnName() async throws {
        let effects = Effects()
        let endpoint = endpoint(effects: effects)
        let initialize = await endpoint.respond(to: post(#"""
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"claude-code","title":"Claude Code","version":"2"}}}
            """#))
        #expect(initialize.status == 200)
        let session = try #require(initialize.headers[HTTPHeaderName.sessionID])

        let list = await endpoint.respond(to: post(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#, session: session))
        #expect(String(decoding: list.body, as: UTF8.self).contains("update_conversations"))

        let id = try receive(on: work)
        let call = await endpoint.respond(to: post(#"""
            {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"update_conversations","arguments":{"ids":["\#(id)"],"action":"star"}}}
            """#, session: session))
        #expect(call.status == 200)
        #expect(await effects.toasts == ["Claude Code starred 1 conversation"])
    }

    @Test func answersAnAgentOverTheSocket() async throws {
        let listener = try endpoint(effects: Effects()).listener(port: 0)
        let (states, ready) = AsyncStream.makeStream(of: NWListener.State.self)
        listener.stateUpdateHandler = { ready.yield($0) }
        listener.start(queue: .global())
        defer { listener.cancel() }
        for await state in states {
            if case .ready = state { break }
        }
        let port = try #require(listener.port?.rawValue)

        var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/mcp")))
        request.httpMethod = "POST"
        for (name, value) in post("").headers where name != "Host" { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"codex","version":"1"}}}"#.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: HTTPHeaderName.sessionID) != nil)
        #expect(String(decoding: data, as: UTF8.self).contains(#""name":"bMail""#))
    }

    @Test func parsesARequestOnceItIsAllIn() throws {
        let whole = Data("POST /mcp?x=1 HTTP/1.1\r\nHost: 127.0.0.1:6245\r\nContent-Length: 4\r\n\r\nabcd".utf8)
        #expect(HTTPRequest.parse(whole.dropLast()) == nil)
        let request = try #require(HTTPRequest.parse(whole))
        #expect(request.method == "POST")
        #expect(request.path == "/mcp")
        #expect(request.body == Data("abcd".utf8))
    }

    private actor Effects {
        var toasts: [String] = []

        func record(_ effect: AgentEffect) {
            if case let .apply(_, toast) = effect { toasts.append(toast) }
        }
    }

    private func endpoint(effects: Effects) -> AgentEndpoint {
        AgentEndpoint(
            tools: AgentTools(store: store) { _ in .organize },
            token: { "secret" },
            perform: { await effects.record($0) }
        )
    }

    private func post(_ body: String, token: String? = "secret", session: String? = nil) -> HTTPRequest {
        var headers = [
            "Host": "127.0.0.1:6245", "Content-Type": "application/json", "Accept": "application/json, text/event-stream",
        ]
        headers["Authorization"] = token.map { "Bearer \($0)" }
        headers[HTTPHeaderName.sessionID] = session
        return HTTPRequest(method: "POST", headers: headers, body: Data(body.utf8), path: "/mcp")
    }

    private func receive(on account: Account) throws -> Conversation.ID {
        var changes = ChangeSet()
        let conversation = Conversation(
            id: UUID(), accountID: account.id, subject: "Q3 numbers", folder: .inbox, isRead: false, isStarred: false,
            snoozedUntil: nil, lastMessageAt: .now, lastOutboundAt: nil
        )
        changes.conversations = [conversation]
        try store.merge(changes, source: "server")
        return conversation.id
    }
}
