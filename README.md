# bMail

A native macOS mail client for Gmail and your own domains. Every view reads a local cache and every action lands there first, so nothing waits on the network.

Gmail syncs straight from the app. Your own domains go through a small api that you host yourself. It sends and receives through [Resend](https://resend.com), keeps mail in Postgres on [Neon](https://neon.tech), stores attachments in [Cloudflare R2](https://developers.cloudflare.com/r2/) and serves open and click tracking. There is no shared bMail server. The app asks for your api's address when you sign in.

## Host your api

You need accounts at Neon, Resend, Cloudflare and [Vercel](https://vercel.com). Their free plans are enough to start. You also need a domain you can add DNS records to and Node 24 with pnpm on your Mac for the one-time setup. The api has nothing Vercel-specific in it, so any host that runs Node 24 works too.

### 1. Clone and install

```sh
git clone https://github.com/SiebeBaree/bMail.git
cd bMail
pnpm install
```

### 2. Pick the api's address

Choose a subdomain for the api, like `mail-api.example.com`. You add it to Vercel in step 6. Use a custom domain, not the `vercel.app` one. Vercel's deployment protection blocks its own domains for anyone outside your team, Resend and the app included.

### 3. Create the database

Create a Neon project, copy its connection string and run the migrations against it:

```sh
export DATABASE_URL="postgresql://...neon.tech/neondb?sslmode=require"
export ALLOWED_EMAILS="you@example.com"
pnpm db:migrate
```

### 4. Create your account

```sh
pnpm --filter api password you@example.com
```

This prints a password. Put it in your password manager. Running it again replaces the password and signs out every Mac that was signed in, which is also how you recover a lost one.

Skip this step if you'll only sign in with Google or Apple.

### 5. Set up Resend and R2

In Resend:

1. Create an API key with full access. The api adds and verifies your domains with it.
2. Add a webhook for `https://mail-api.example.com/webhooks/resend` with the events `email.received`, `email.sent`, `email.delivered`, `email.delivery_delayed`, `email.bounced`, `email.complained` and `email.failed`. Copy its signing secret.

In Cloudflare, create an R2 bucket and an R2 API token with Object Read & Write on that bucket. Note the account id, the access key id and the secret access key.

### 6. Deploy to Vercel

Import the repository into Vercel with the root directory set to `apps/api`. Vercel picks the Fastify preset. Add these environment variables before the first deploy:

| Variable                                                                 | Value                                                                                                        |
| ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `DATABASE_URL`                                                           | The Neon connection string from step 3                                                                       |
| `ALLOWED_EMAILS`                                                         | Your email. Separate several with commas                                                                     |
| `PUBLIC_URL`                                                             | `https://mail-api.example.com`                                                                               |
| `BETTER_AUTH_SECRET`                                                     | Output of `openssl rand -base64 32`                                                                          |
| `TRACKING_SECRET`                                                        | Another `openssl rand -base64 32`                                                                            |
| `RESEND_API_KEY`                                                         | `re_...` from step 5                                                                                         |
| `RESEND_WEBHOOK_SECRET`                                                  | `whsec_...` from step 5                                                                                      |
| `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET` | From step 5                                                                                                  |
| `GOOGLE_CLIENT_ID`                                                       | Optional. `120617231468-9n56accj81imqh2a7638n8hsstlfad5e.apps.googleusercontent.com` turns on Google sign-in |
| `APPLE_BUNDLE_ID`                                                        | Optional. `be.baree.mail` turns on Sign in with Apple                                                        |
| `SENTRY_DSN`                                                             | Optional                                                                                                     |

Then add `mail-api.example.com` under the project's domains and point its DNS where Vercel tells you. `https://mail-api.example.com/health` should answer once it's live.

### 7. Install bMail and sign in

Download the DMG from the [latest release](https://github.com/SiebeBaree/bMail/releases/latest) and drag bMail into Applications. Open it, enter `mail-api.example.com` as your server and sign in with the password from step 4, or with Google or Apple.

### 8. Add your domain

In Settings, add your domain. bMail lists the DNS records it needs: Resend's records for sending and receiving, a DMARC record and a `t` CNAME for tracking. Add `t.example.com` to the Vercel project's domains as well, or tracked mail keeps using the api's own address.

## Who can use your api

Only the emails in `ALLOWED_EMAILS` can have an account, and nobody can sign up with a password. An account comes from one of two places:

- Google or Apple, which have verified that you own the email.
- `pnpm --filter api password`, which needs your database's connection string.

Anyone else who finds your api gets nowhere, even if they know your email.

## Build it yourself

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
cd apps/macos
xcodegen
open Mail.xcodeproj
```

`apps/macos/project.yml` is the source of truth for the Xcode project. Before building, set `DEVELOPMENT_TEAM` to your own team and `PRODUCT_BUNDLE_IDENTIFIER` to a bundle id you own. Gmail and Google sign-in need an iOS-type Google OAuth client for that bundle id. Put its id in `GOOGLE_CLIENT_ID` in `project.yml` and on your api.

## Develop

[AGENTS.md](AGENTS.md) explains how the code is laid out and how to run the app against a local api. Before you finish a change, run `pnpm typecheck && pnpm lint && pnpm test && pnpm format` at the root, and `swift test` in `apps/macos/MailKit` for app changes.

## License

[MIT](LICENSE)
