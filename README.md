# bMail

A native mail client for Mac and iPhone, for Gmail and your own domains. Every view reads a local cache and every action lands there first, so nothing waits on the network.

Gmail syncs straight from the app, and there's no bMail account. Your own domains and open tracking go through a small api that you host yourself. It sends and receives through [Resend](https://resend.com) and serves open and click tracking. Mail lives in Postgres on [Neon](https://neon.tech), attachments in a Vercel Blob store or [Cloudflare R2](https://developers.cloudflare.com/r2/). There is no shared bMail server.

## Install bMail

Download the DMG from the [latest release](https://github.com/SiebeBaree/bMail/releases/latest) and drag bMail into Applications. Open it and pick Gmail to sign in with Google. That's all Gmail needs.

## Host your api

You only need it for addresses on your own domains and for tracking. You need a [Vercel](https://vercel.com) account and, once you add a domain, a Resend account. Their free plans are enough.

### 1. Deploy

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2FSiebeBaree%2FbMail&root-directory=apps%2Fapi&project-name=bmail&repository-name=bmail&stores=%5B%7B%22type%22%3A%22integration%22%2C%22integrationSlug%22%3A%22neon%22%2C%22productSlug%22%3A%22neon%22%2C%22protocol%22%3A%22storage%22%7D%2C%7B%22type%22%3A%22blob%22%2C%22access%22%3A%22private%22%7D%5D&redirect-url=https%3A%2F%2Fgetbmail.si%2Fconnect)

Vercel copies this repository to your GitHub, adds a Neon database and a private Blob store, then deploys `apps/api`. The build migrates the database. There are no environment variables to fill in.

When the deploy finishes, Vercel sends you back to bMail, which asks once before it connects. The first bMail to connect to a new server owns it, and your other devices get the connection through iCloud Keychain. To connect a server deployed earlier, add an address on your own domain in bMail, pick Connect existing and enter the server's address.

The project's `vercel.app` address works for everything. To give the api your own address, add it under the project's domains on Vercel.

### 2. Add your domain

In Settings, add an address on your own domain. The first time, bMail asks for a Resend [API key](https://resend.com/api-keys) with full access. Your server checks it, creates the Resend webhook it needs and keeps both in its database.

bMail then lists the DNS records your domain needs: Resend's records for sending and receiving, a DMARC record and a `t` CNAME for tracking. Add `t.example.com` to the Vercel project's domains as well, or tracked mail keeps using the api's own address.

### Hosting somewhere else

Nothing in the api needs Vercel. Any host that runs Node 24 works: set `DATABASE_URL`, run `pnpm db:migrate` once per release and set the four `R2_` variables for attachments. [`apps/api/.env.example`](apps/api/.env.example) lists every variable.

### Upgrading a server from before claiming

The next deploy migrates the database, and every device that was signed in stays signed in. `ALLOWED_EMAILS`, `BETTER_AUTH_SECRET` and `APPLE_BUNDLE_ID` can go. `TRACKING_SECRET` and the Resend variables keep working, so mail you already sent stays tracked.

## Who can use your api

Nobody signs up. The first bMail to connect to a new server owns it, and every request after that needs the token it got. bMail keeps that token in iCloud Keychain, so your Mac and iPhone share it.

If you lose every device, or someone claimed your server before you did, add a `CLAIM_CODE` environment variable with a long value to the Vercel project and redeploy. Connecting with that code makes you the owner again and signs out every other device. Your mail stays where it is.

## Build it yourself

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd apps/macos   # or apps/ios for the iPhone app
xcodegen
open Mail.xcodeproj
```

Each app's `project.yml` is the source of truth for its Xcode project. Before building, set `DEVELOPMENT_TEAM` to your own team and `PRODUCT_BUNDLE_IDENTIFIER` to a bundle id you own, the same one in both. Gmail needs an iOS-type Google OAuth client for that bundle id. Put its id in `GOOGLE_CLIENT_ID` in both `project.yml` files.

Release builds of the Mac app update themselves from this repository's releases. To ship your own, point `SUFeedURL` in `apps/macos/project.yml` at your repository, put the public key from Sparkle's `generate_keys` in `SUPublicEDKey` and the private one in your repository's `SPARKLE_PRIVATE_KEY` secret.

## Develop

[AGENTS.md](AGENTS.md) explains how the code is laid out and how to run the app against a local api. Before you finish a change, run `pnpm typecheck && pnpm lint && pnpm test && pnpm format` at the root, and `swift test` in `apps/macos/MailKit` for app changes.

## License

[MIT](LICENSE)
