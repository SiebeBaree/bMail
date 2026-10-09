import Foundation
import HTTPTypes
import MailCore
import OpenAPIRuntime
import Testing

@testable import Providers

@Suite struct AddressListTests {
    @Test func splitsOnCommasOutsideQuotesAndBrackets() {
        let addresses = AddressList.parse(#""Peeters, Lena" <Lena@Peeters.be>, tom@northfund.vc, Pieter Claes <pieter@northfund.vc>"#)
        #expect(addresses == [
            Address(name: "Peeters, Lena", email: "lena@peeters.be"),
            Address(email: "tom@northfund.vc"),
            Address(name: "Pieter Claes", email: "pieter@northfund.vc"),
        ])
    }

    @Test func ignoresEmptyHeaders() {
        #expect(AddressList.parse("").isEmpty)
    }
}

@Suite struct MIMEMessageTests {
    private func render(subject: String = "Proposal", attachments: [OutgoingAttachment] = []) throws -> String {
        let message = OutgoingMessage(
            conversationID: UUID(), accountID: UUID(), from: Address(name: "Siebe Baree", email: "siebe@gmail.com"),
            to: [Address(name: "Jan Wouters", email: "jan@wouters.be")], bcc: [Address(email: "me@baree.be")],
            subject: subject, html: "<p>Hi Jan</p>", text: "Hi Jan", attachments: attachments
        )
        let mime = MIMEMessage(message: message, inReplyTo: "<parent@x>", references: ["<root@x>", "<parent@x>"], messageID: "<id@baree.mail>")
        return String(decoding: try mime.render(), as: UTF8.self)
    }

    @Test func carriesThreadingHeadersAndBothBodies() throws {
        let raw = try render()
        #expect(raw.contains("From: \"Siebe Baree\" <siebe@gmail.com>\r\n"))
        #expect(raw.contains("In-Reply-To: <parent@x>\r\n"))
        #expect(raw.contains("References: <root@x> <parent@x>\r\n"))
        #expect(raw.contains("Bcc: me@baree.be\r\n"))
        #expect(raw.contains("Content-Type: multipart/alternative"))
        #expect(raw.contains(Data("<p>Hi Jan</p>".utf8).base64EncodedString()))
        #expect(raw.contains(Data("Hi Jan".utf8).base64EncodedString()))
    }

    @Test func encodesSubjectsThatArentASCII() throws {
        #expect(try render(subject: "Offerte voor Q4 ✓").contains("Subject: =?UTF-8?B?\(Data("Offerte voor Q4 ✓".utf8).base64EncodedString())?="))
    }

    @Test func lineBreaksCantAddHeaders() throws {
        let raw = try render(subject: "Invoice\r\nBcc: x@evil.example\nReply-To: pay@evil.example")
        #expect(raw.contains("Subject: InvoiceBcc: x@evil.exampleReply-To: pay@evil.example\r\n"))
        #expect(!raw.contains("\r\nReply-To:"))
    }

    @Test func wrapsAttachmentsInMultipartMixed() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "proposal-\(UUID()).pdf")
        try Data("%PDF".utf8).write(to: file)
        let raw = try render(attachments: [OutgoingAttachment(filename: "proposal.pdf", contentType: "application/pdf", size: 4, fileURL: file)])
        #expect(raw.contains("Content-Type: multipart/mixed"))
        #expect(raw.contains(#"Content-Disposition: attachment; filename="proposal.pdf""#))
        #expect(raw.contains(Data("%PDF".utf8).base64EncodedString()))
    }
}

@Suite struct GmailMappingTests {
    let mapping = GmailMapping(accountID: UUID())

    private func thread(labels: [[String]], headers extra: String = "") throws -> Gmail.Thread {
        let messages = labels.enumerated().map { index, labels in
            """
            {"id": "m\(index)", "threadId": "t1", "labelIds": \(labels), "snippet": "It&#39;s fine", "internalDate": "\(1_760_000_000_000 + index * 60_000)",
             "payload": {"mimeType": "multipart/alternative", "headers": [
                {"name": "From", "value": "\(labels.contains("SENT") ? "Siebe <siebe@gmail.com>" : "Lena Peeters <lena@peeters.be>")"},
                {"name": "To", "value": "siebe@gmail.com"}, {"name": "Subject", "value": "Contract"},
                {"name": "Message-ID", "value": "<m\(index)@mail.gmail.com>"}\(extra)],
              "parts": [
                {"partId": "0", "mimeType": "text/plain", "body": {"size": 5, "data": "SGVsbG8"}},
                {"partId": "1", "mimeType": "text/html", "body": {"size": 12, "data": "PHA-SGVsbG88L3A-"}},
                {"partId": "2", "mimeType": "application/pdf", "filename": "contract.pdf", "body": {"size": 1200, "attachmentId": "ANGjdJ"}}]}}
            """
        }
        let json = #"{"id": "t1", "messages": [\#(messages.joined(separator: ","))]}"#
        return try JSONDecoder().decode(Gmail.Thread.self, from: Data(json.utf8))
    }

    @Test func bodiesDecodeInTheirOwnCharset() throws {
        // "café" in ISO-8859-1, where é is the single byte E9.
        let json = #"""
        {"id": "m1", "threadId": "t1", "payload": {"mimeType": "text/plain",
         "headers": [{"name": "Content-Type", "value": "text/plain; charset=\"ISO-8859-1\""}],
         "body": {"size": 4, "data": "Y2Fm6Q"}}}
        """#
        let message = mapping.message(try JSONDecoder().decode(Gmail.Message.self, from: Data(json.utf8)))
        #expect(message.text == "café")
    }

    @Test func draftsAreLeftOut() throws {
        let (_, messages) = try #require(mapping.conversation(try thread(labels: [["INBOX"], ["DRAFT"]])))
        #expect(messages.count == 1)
    }

    @Test func labelsBecomeFolderReadAndStarredState() throws {
        let (inbox, _) = try #require(mapping.conversation(try thread(labels: [["INBOX", "UNREAD"], ["SENT"]])))
        #expect(inbox.folder == .inbox)
        #expect(inbox.isRead == false)
        #expect(inbox.lastOutboundAt != nil)

        let (archived, _) = try #require(mapping.conversation(try thread(labels: [["STARRED"]])))
        #expect(archived.folder == .done)
        #expect(archived.isStarred)
        #expect(archived.isRead)

        let (trashed, _) = try #require(mapping.conversation(try thread(labels: [["TRASH"]])))
        #expect(trashed.folder == .trash)
    }

    @Test func messagesKeepBodiesAttachmentsAndTheirOwnIds() throws {
        let (conversation, messages) = try #require(mapping.conversation(try thread(labels: [["INBOX"], ["SENT"]])))
        let first = try #require(messages.first)
        #expect(first.text == "Hello")
        #expect(first.html == "<p>Hello</p>")
        #expect(first.snippet == "It's fine")
        #expect(first.from == Address(name: "Lena Peeters", email: "lena@peeters.be"))
        #expect(first.attachments.map(\.filename) == ["contract.pdf"])
        #expect(first.attachments.first?.remoteID == "m0/ANGjdJ")
        #expect(messages.last?.direction == .outbound)
        // The same Gmail ids always map to the same rows, so a resync updates instead of duplicating.
        #expect(conversation.id == mapping.conversationID(thread: "t1"))
        #expect(first.id == mapping.messageID("m0"))
    }
}

extension GmailMappingTests {
    @Test func sentMailKeepsTheIdItHadInTheOutbox() throws {
        let outboxID = UUID()
        let header = #", {"name": "X-Bmail-ID", "value": "\#(outboxID.uuidString.lowercased())"}"#
        let (_, messages) = try #require(mapping.conversation(try thread(labels: [["INBOX"], ["SENT"]], headers: header)))
        #expect(messages.last?.id == outboxID)
        // Only your own sent copy: anyone can put the header on mail they send you.
        #expect(messages.first?.id == mapping.messageID("m0"))
    }

    @Test func listMailOffersOneClickUnsubscribe() throws {
        let headers = #"""
            , {"name": "List-Unsubscribe", "value": "<mailto:leave@list.example?subject=stop>, <https://list.example/u/1>"},
            {"name": "List-Unsubscribe-Post", "value": "List-Unsubscribe=One-Click"}
            """#
        let (_, messages) = try #require(mapping.conversation(try thread(labels: [["INBOX"]], headers: headers)))
        let unsubscribe = try #require(messages.first?.unsubscribe)
        #expect(unsubscribe.url == URL(string: "https://list.example/u/1"))
        #expect(unsubscribe.mailto == URL(string: "mailto:leave@list.example?subject=stop"))
        #expect(unsubscribe.isOneClick)
    }
}

@Suite struct GmailSyncPositionTests {
    @Test func aFirstSyncInProgressSurvivesTheStore() {
        let page = GmailProvider.SyncPosition.InitialPage(historyID: "9001", pageToken: "next", fetched: 50)
        guard case let .initial(restored) = GmailProvider.SyncPosition(GmailProvider.SyncPosition.initial(page).cursor) else {
            Issue.record("expected the first sync to resume")
            return
        }
        #expect(restored.historyID == "9001")
        #expect(restored.pageToken == "next")
        #expect(restored.fetched == 50)
    }

    @Test func aPlainHistoryIdFollowsHistory() {
        guard case .history("9001") = GmailProvider.SyncPosition("9001") else {
            Issue.record("expected a history cursor")
            return
        }
    }
}

/// Answers every request the way the api answers a delete: 204 and no body.
private struct NoContent: ClientTransport {
    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        (HTTPResponse(status: .noContent), nil)
    }
}

@Suite struct ServerAdminTests {
    @Test func deletesSucceedOnTheirEmptyAnswer() async throws {
        let admin = ServerAdmin(connection: ServerConnection(baseURL: URL(string: "https://api.example")!, transport: NoContent()))
        let id = UUID()
        #expect(try await admin.deleteLabel(id).removedLabelIDs == [id])
        #expect(try await admin.removeDomain(id).removedDomainIDs == [id])
        #expect(try await admin.removeMailbox(id).removedAccountIDs == [id])
    }
}
