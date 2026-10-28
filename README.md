# bMail

A fast mail app for Mac and iPhone. It reads Gmail and addresses on your own domain in one inbox. It's free, open source and has no bMail account.

## What it does

- **Gmail and your own domain side by side.** Add several accounts and read them together or one at a time.
- **Nothing waits on the network.** A copy of your mail lives in a database on your device. Archive, label, star and write offline, and bMail syncs when you're back.
- **Keyboard first.** Every action has a shortcut. `⌘K` opens a command palette and `?` lists every shortcut.
- **Undo anything.** Every action shows a toast with Undo. Sent mail waits ten seconds, so `Z` unsends too.
- **Open and click tracking, if you want it.** Turn it on per message with `⌘⇧T`. Apple's privacy proxy, link scanners and your own opens don't count. It's off by default.
- **Delivered or Bounced.** Mail sent from your domain shows which one, with the receiving server's own words when it fails.
- **One-click unsubscribe.** When a newsletter supports it, bMail sends the request itself.
- **Search on your device.** Results show as you type, offline too.
- **AI on your own key.** Tab completion while you write and automatic labels on new mail. Requests go straight from your device to the provider you pick.
- **Agents on your Mac.** Claude Code and other MCP clients can read, organize and send mail. You set what each account allows, from Off to Send.

## What you need

Gmail needs nothing but the app. Everything else is optional and only needed for the feature next to it.

| You want                    | You need                                                             |
| --------------------------- | -------------------------------------------------------------------- |
| Gmail                       | The app                                                              |
| An address on your domain   | Your own server, a Resend account and a domain whose DNS you control |
| Open and click tracking     | Your own server                                                      |
| AI completion and labelling | An API key from an AI provider                                       |
| Agents                      | The Mac app                                                          |

"Your own server" is a small api that you deploy once with one button. There is no shared bMail server, so nobody else sees your mail. The free plans of Vercel, Neon and Resend are enough for one person.

### Every service, and why

| Service                                                                  | What bMail uses it for                                                                                     | When you need it                                                        | Can you swap it?                                                                                                             |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| [Vercel](https://vercel.com)                                             | Runs your server.                                                                                          | Your own domain or tracking.                                            | Yes. Any host that runs Node 24 works.                                                                                       |
| [Neon](https://neon.tech)                                                | The server's Postgres database. It holds mail on your domains, your addresses, labels and tracking events. | Whenever you run a server.                                              | Not without code changes. The server uses Neon's serverless driver.                                                          |
| [Vercel Blob](https://vercel.com/docs/vercel-blob)                       | Files. Attachments you send, and a copy of every message you receive on your domain with its attachments.  | As soon as you receive mail on your domain. Receiving fails without it. | Yes, with Cloudflare R2. You need one of the two.                                                                            |
| [Cloudflare R2](https://developers.cloudflare.com/r2/)                   | The same as Vercel Blob.                                                                                   | Only if you host outside Vercel or prefer it.                           | Yes, with Vercel Blob.                                                                                                       |
| [Resend](https://resend.com)                                             | Sends and receives mail on your domain and reports whether it was delivered.                               | Once you add a domain.                                                  | No. The server is built on it.                                                                                               |
| A domain                                                                 | Your addresses. You add the DNS records bMail shows you.                                                   | For addresses on your own domain.                                       | No.                                                                                                                          |
| An AI provider                                                           | Tab completion and automatic labels.                                                                       | Only if you turn AI on.                                                 | Pick any of Anthropic, OpenAI, Google Gemini, xAI, DeepSeek, Z.ai, Moonshot, Mistral, Groq, OpenRouter or Vercel AI Gateway. |
| iCloud Keychain                                                          | Shares your Gmail sign-in and your server's address and token between your Mac and iPhone.                 | Only to skip setting up each device.                                    | Without it, set up each device on its own.                                                                                   |
| [Sentry](https://sentry.io)                                              | Error reports from your server.                                                                            | Never. Set `SENTRY_DSN` if you want them.                               | Logs on stdout work without it.                                                                                              |
| [Google OAuth client](https://console.cloud.google.com/apis/credentials) | Lets the app sign in to Gmail.                                                                             | Only when you build the app yourself. Release builds include one.       | No.                                                                                                                          |

### How mail moves

```
Gmail         bMail  <->  Google

Your domain   bMail  <->  your server  <->  Resend  <->  everyone else's mail servers
                              |
                              +-- Neon: mail, addresses, labels, tracking
                              +-- Vercel Blob or R2: attachments and raw messages
```

AI requests go from your device to your AI provider. Neither touches your server.

## Install bMail

Download the DMG from the [latest release](https://github.com/SiebeBaree/bMail/releases/latest) and drag bMail into Applications. It needs macOS 27. Open it and pick Gmail to sign in with Google. That's all Gmail needs. The Mac app updates itself.

The iPhone app isn't in the App Store yet. To run it, [build it yourself](#build-it-yourself). It needs iOS 27.

## Host your server

You only need this for addresses on your own domain and for tracking.

### 1. Deploy

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2FSiebeBaree%2FbMail&root-directory=apps%2Fapi&project-name=bmail&repository-name=bmail&stores=%5B%7B%22type%22%3A%22integration%22%2C%22integrationSlug%22%3A%22neon%22%2C%22productSlug%22%3A%22neon%22%2C%22protocol%22%3A%22storage%22%7D%2C%7B%22type%22%3A%22blob%22%2C%22access%22%3A%22private%22%7D%5D&redirect-url=https%3A%2F%2Fgetbmail.si%2Fconnect)

Vercel copies this repository to your GitHub, adds a Neon database and a private Blob store, then deploys `apps/api`. The build sets up the database. You don't fill in any environment variables.

When the deploy finishes, Vercel sends you back to bMail, which asks once before it connects. The first bMail to connect owns the server. Your other devices get the connection through iCloud Keychain.

To connect a server you deployed earlier, add an address on your own domain in bMail, pick Connect existing and enter the server's address.

The project's `vercel.app` address works for everything. To use your own, add it under the project's domains on Vercel.

### 2. Add your domain

In Settings, add an address on your own domain. The first time, bMail asks for a Resend [API key](https://resend.com/api-keys) with full access. Your server checks it, creates the Resend webhook it needs and keeps both in its database.

bMail then lists the DNS records your domain needs:

- Resend's records for sending and receiving
- a DMARC record
- a `t` CNAME for tracking

Add `t.example.com` to the Vercel project's domains as well, or tracked mail keeps using the server's own address.

### Hosting somewhere else

Nothing in the server needs Vercel. On any host that runs Node 24:

1. Set `DATABASE_URL` to your Neon database.
2. Set `PUBLIC_URL` to the server's https address. Vercel fills this in for you, other hosts don't.
3. Set the four `R2_` variables for attachments.
4. Run `pnpm db:migrate` once per release.

[`apps/api/.env.example`](apps/api/.env.example) lists every variable.

### Upgrading a server from before claiming

The next deploy migrates the database and every device that was signed in stays signed in. You can remove `ALLOWED_EMAILS`, `BETTER_AUTH_SECRET` and `APPLE_BUNDLE_ID`. Keep `TRACKING_SECRET` and the Resend variables, so mail you already sent stays tracked.

## Who can use your server

Nobody signs up. The first bMail to connect to a new server owns it, and every request after that needs the token it got. bMail keeps that token in iCloud Keychain, so your Mac and iPhone share it.

Lost every device, or someone claimed your server first? Add a `CLAIM_CODE` environment variable with a long value to the Vercel project and redeploy. Connecting with that code makes you the owner again and signs out every other device. Your mail stays where it is.

## Build it yourself

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd apps/macos   # or apps/ios for the iPhone app
xcodegen
open Mail.xcodeproj
```

Each app's `project.yml` is the source of truth for its Xcode project. Before you build:

1. Set `DEVELOPMENT_TEAM` to your own team.
2. Set `PRODUCT_BUNDLE_IDENTIFIER` to a bundle id you own, the same in both apps.
3. Create an iOS-type Google OAuth client for that bundle id and put its id in `GOOGLE_CLIENT_ID` in both `project.yml` files. Without it bMail doesn't offer Gmail.

Release builds of the Mac app update themselves from this repository's releases. To ship your own, point `SUFeedURL` in `apps/macos/project.yml` at your repository, put the public key from Sparkle's `generate_keys` in `SUPublicEDKey` and the private one in your repository's `SPARKLE_PRIVATE_KEY` secret.

## Develop

[AGENTS.md](AGENTS.md) explains how the code is laid out and how to run the app against a local server. Before you finish a change, run `pnpm typecheck && pnpm lint && pnpm test && pnpm format` at the root, and `swift test` in `apps/macos/MailKit` for app changes.

## License

[MIT](LICENSE)
