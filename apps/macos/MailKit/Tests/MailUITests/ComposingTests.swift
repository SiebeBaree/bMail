import Foundation
import MailCore
import Testing

@testable import MailUI

@Suite struct ComposingTests {
    let me = Address(name: "Siebe Baree", email: "siebe@baree.be")
    let tom = Address(name: "Tom Verhaegen", email: "tom@northfund.vc")
    let pieter = Address(name: "Pieter Claes", email: "pieter@northfund.vc")
    let lena = Address(name: "Lena Peeters", email: "lena@peeters.be")

    @Test func replyAllLeavesYouOutAndKeepsEveryoneElse() throws {
        let last = message(from: tom, to: [me, pieter], cc: [lena, me], subject: "Seed round timeline")
        let response = try #require(Response(to: [last], mode: .replyAll, ownAddresses: ["siebe@baree.be"]))
        #expect(response.to == [tom, pieter])
        #expect(response.cc == [lena])
    }

    @Test func aReplyToYourOwnMessageGoesToWhoYouWroteTo() throws {
        let last = message(from: me, to: [tom], direction: .outbound, subject: "Proposal")
        let response = try #require(Response(to: [last], mode: .reply, ownAddresses: ["siebe@baree.be"]))
        #expect(response.to == [tom])
    }

    @Test func prefixesDontStack() throws {
        let last = message(from: tom, to: [me], subject: "Re: Fwd: RE: Seed round")
        #expect(Response(to: [last], mode: .reply, ownAddresses: [])?.subject == "Re: Seed round")
        #expect(Response(to: [last], mode: .forward, ownAddresses: [])?.subject == "Fwd: Seed round")
    }

    @Test func aQuoteLeavesOurOpenPixelBehind() {
        let pixel = #"<img src="https://t.baree.be/o/0f8fad5b-d9cb-469f-a165-70867728950e.abc123" width="1" height="1">"#
        #expect(Response.withoutOpenPixels("<p>Hi</p>\(pixel)") == "<p>Hi</p>")
    }

    @Test func switchingAccountsSwapsTheSignatureOnlyWhileItsUntouched() {
        let first = UUID()
        let second = UUID()
        Signatures.set("Siebe", for: first)
        Signatures.set("Siebe, bMail", for: second)
        defer {
            Signatures.set("", for: first)
            Signatures.set("", for: second)
        }
        #expect(Signatures.swapped(in: "Hi Tom\n\nSiebe", from: first, to: second) == "Hi Tom\n\nSiebe, bMail")
        #expect(Signatures.swapped(in: "Hi Tom\n\nSiebe x", from: first, to: second) == nil)
        #expect(Signatures.swapped(in: "", from: nil, to: second) == "\n\nSiebe, bMail")
    }

    @Test func twoFilesWithTheSameNameBothGoOut() throws {
        let messageID = UUID()
        defer { try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Outbox/\(messageID.uuidString)")) }
        let first = try OutboxFiles.write(Data("one".utf8), named: "Photo.jpg", for: messageID)
        let second = try OutboxFiles.write(Data("two".utf8), named: "Photo.jpg", for: messageID)
        #expect(first.filename == "Photo.jpg")
        #expect(second.filename == "Photo 2.jpg")
        #expect(try String(contentsOf: first.fileURL, encoding: .utf8) == "one")
    }

    private func message(from: Address, to: [Address], cc: [Address] = [], direction: Direction = .inbound, subject: String) -> Message {
        Message(
            id: UUID(), conversationID: UUID(), accountID: UUID(), direction: direction, deliveryStatus: nil,
            messageIDHeader: nil, from: from, to: to, cc: cc, bcc: [], replyTo: [], subject: subject, html: nil,
            text: "Hello", snippet: "Hello", sentAt: .now, trackingEnabled: false, attachments: [], links: []
        )
    }
}
