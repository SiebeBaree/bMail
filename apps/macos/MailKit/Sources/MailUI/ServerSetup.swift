import Foundation
import Providers

/// Getting a server, the same on the Mac and the iPhone: a new one through Vercel's deploy flow, or one you already run.
public enum ServerSetup {
    /// Vercel's deploy flow for the api. It copies the repository to your GitHub, adds a Neon database and a private Blob
    /// store, and when the deploy is done sends you to getbmail.si/connect, which hands the new address back to bMail
    /// through a `bmail://connect` link.
    public static let deployURL: URL = {
        var components = URLComponents(string: "https://vercel.com/new/clone")!
        let stores = #"[{"type":"integration","integrationSlug":"neon","productSlug":"neon","protocol":"storage"},{"type":"blob","access":"private"}]"#
        components.queryItems = [
            URLQueryItem(name: "repository-url", value: "https://github.com/SiebeBaree/bMail"),
            // Not in Vercel's docs, but it keeps the whole monorepo and roots the project at the api.
            URLQueryItem(name: "root-directory", value: "apps/api"),
            URLQueryItem(name: "project-name", value: "bmail"),
            URLQueryItem(name: "repository-name", value: "bmail"),
            URLQueryItem(name: "stores", value: stores),
            URLQueryItem(name: "redirect-url", value: "https://getbmail.si/connect"),
        ]
        return components.url!
    }()

    /// The server a `bmail://connect?server=<address>` link points at. Nil for any other link.
    public static func server(in link: URL) -> URL? {
        guard link.scheme == "bmail", link.host() == "connect",
            let address = URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "server" })?.value
        else { return nil }
        return ServerConnection.baseURL(from: address)
    }
}
