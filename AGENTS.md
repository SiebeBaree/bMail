# Mail

A native mail client for Mac and iPhone, for Gmail and your own domains. Gmail syncs straight from the app. Your own domains run through a small api that wraps Resend for receiving and sending, stores mail in Neon and serves per-email open and click tracking. The app is local-first: every view reads a SQLite cache and every action writes there first, so nothing in the UI waits on the network.

## This codebase

Turborepo monorepo: the macOS app (`apps/macos`, Swift), the iPhone app (`apps/ios`, Swift), a Fastify api (`apps/api`), the Next.js marketing site (`apps/web`) and shared TypeScript packages under `packages/`. The api deploys on Vercel from a deploy button but runs on any Node host: Neon for Postgres, a private Vercel Blob store or Cloudflare R2 (S3 api) for files.

## Principles

- Yagni. Fight for the smallest change that makes the behavior correct. Do not add abstractions for imagined futures and do not preserve complexity just because it exists.
- Typesafety over defensiveness. `any` is banned (lint enforced). The contract schemas are the single source of truth for the wire; the Swift client is generated from them, so if the app and the api disagree about a shape, the fix is in `@repo/contracts`, never a local cast or a hand-written model.
- Comments only for what the code cannot show: framework magic, security trade-offs, policy, traps. Never restate the code. No em-dashes and no oxford commas anywhere, including comments.
- Run `pnpm typecheck && pnpm lint && pnpm test && pnpm format` at the repo root before finishing an api change, and build and test the Swift package for an app change. Lint warnings fail the build on purpose.
- Do not create documentation files (README, docs/) unless explicitly asked.

## Glossary

- **Contract**: a Zod schema in `@repo/contracts` describing one api input or output (dates travel as ISO strings). Schemas with `.meta({ id })` become named types in the OpenAPI document and so in Swift.
- **Module** (api): a vertical slice under `apps/api/src/modules/` with routes, a service (logic and not-found semantics) and a repo (database access). A module with one trivial route may skip the layers.
- **Your domains / custom domains**: domains added through the api and verified in Resend. A **mailbox** is an address on one, a row in our database; Resend accepts mail for every address and the api routes it.
- **Seq**: every synced row's position in its user's change stream, set by a Postgres trigger. The app syncs with `GET /sync?cursor=<seq>`.
- **Mutation** (app): every user action, applied to SQLite first and then flushed to the provider by a persistent queue.
- **Provider** (app): one per account kind (Gmail, your domains). Translates between its wire format and the app's models and nothing more.
- **Session** (app): `MailSession`, the cache, your server, the sync engine and every action that changes mail. Each app's `AppModel` owns one and adds its own navigation, so sending, undo and connecting accounts behave the same on both. There's no account to sign in to: the session is ready once it has a mail account or a server.

## How a change flows

Contracts first, then api, then app. Change the Zod schema, implement the route against it, run `pnpm openapi` to regenerate `apps/macos/MailKit/Sources/APIClient/openapi.json`, then build the Swift package so the generated client picks it up. For breaking changes use expand-contract: shipped app builds keep calling the old shape until they update.

## Testing: when and what

Api modules are tested by injecting requests into a fully built app on PGlite (in-memory Postgres running the real migrations, triggers included) with a fake Resend gateway. Write one test per meaningful behavior of an endpoint, including the interesting rejections. Pure functions with real logic (address parsing, html instrumentation, tracking tokens) get unit tests. In Swift, test the store, the sync engine against a fake provider, mutations and serialization. No smoke tests, no tests that mock half the app.

## The apps

`apps/macos` and `apps/ios` are generated with XcodeGen: each `project.yml` is the source of truth and `Mail.xcodeproj` is gitignored, so run `xcodegen` in the app's folder after pulling. Everything below the views lives in the `MailKit` Swift package at `apps/macos/MailKit`, which both apps use, and is tested with `swift test` there:

- `DesignSystem`: Vercel's tokens (colors, Geist, radii, motion), buttons, key caps, toasts. Views never hardcode a color.
- `MailCore`: the SQLite cache (GRDB + SQLiteData), `MailStore` (every write), `MailSyncEngine` (pull, push, outbox) and the provider protocol.
- `APIClient`: generated at build time from `openapi.json` by swift-openapi-generator.
- `Providers`: `ServerProvider` for your domains, `GmailProvider`, OAuth with PKCE and a MIME builder.
- `Assist`: AI on your own key. The provider client (Anthropic's Messages, Chat Completions for everyone else, each with its own reasoning parameter), provider and model logos from LobeHub's icon set, the settings and the prompts for tab completion and auto labelling.
- `MailUI`: what both apps' views share: `MailSession`, the queries behind the list and the reader, message rendering and its tracker blocking (`MailPages`), and the composer's rules.
- `Agents` (Mac only): the MCP server agents on your Mac connect to, its tools and the access level of each account.

Each app target holds its views, grouped by feature, plus `AppModel`. The Mac's adds `Command` (the keymap that drives keys, the palette, the shortcut sheet and the menu bar). The iPhone's is built for touch: swipes and long presses instead of keys, a sheet for the composer and toasts in a window of their own so they show over sheets.

Run the Mac app against a local api: start the api (`PORT=4317 PUBLIC_URL=http://localhost:4317 pnpm --filter api dev`), seed it once (`SEED_DATABASE_URL=<dev database> pnpm --filter api seed`; the seed never touches `DATABASE_URL`, claims the database and prints the token for `-sessionToken`), build, then `open "…/bMail.app" --args -serverURL http://localhost:4317 -sessionToken <token>`. The iPhone app takes the same arguments in the simulator: `xcrun simctl launch booted be.baree.mail -serverURL http://localhost:4317 -sessionToken <token>`. Debug builds of both also accept `-resetCache YES`.

## Things you need to know

- Views read with `@FetchAll`/`@Fetch` and never write. Writes go through `MailStore`, which keeps derived list columns, the search index and pending mutations consistent; a sync that races your own change replays the pending mutations on top.
- Raw GRDB SQL binds a `UUID` as a blob, but the tables store ids as lowercase text (StructuredQueries' format). Bind `uuidString.lowercased()` in raw SQL, or use the query builder.
- Gmail ids become our ids through `UUID(stableFrom:)`, so a resync updates rows instead of duplicating them.
- The Google OAuth client id lives in `project.yml` (`GOOGLE_CLIENT_ID`, an iOS-type Google client). Without it Gmail isn't offered.
- Gmail tokens and the server link (address and owner token) are synced Keychain items, so what you add on the Mac shows up on the iPhone through iCloud Keychain, and removing it removes it everywhere. The Mac needs `keychain-access-groups` for that, which only launches with an embedded provisioning profile: `release.yml` embeds the `DEVELOPER_ID_PROVISIONING_PROFILE` secret when it's set and strips the entitlement otherwise, and `Keychain` falls back to items on this device.
- Labels on Gmail mail are Gmail labels (`MailLabel.accountID`, created and synced through Gmail's api); labels on mail on your domains live on your server. Views and agents show labels by name, so a name on both is one label.
- Sync correctness lives in `packages/db/migrations/0001_sync_seq.sql`: `next_change` holds a row lock on the user's counter until commit, so rows commit in seq order and a cursor never skips a late commit. Every synced table needs the trigger.
- Tracked mail is instrumented only on the way out. The stored html is what was written, which is what lets the app show your own sent mail without counting an open. The app also blocks every `t.*` tracking host in its web views.
- Ids for new rows the app creates (messages, conversations, mailboxes) are generated by the app. That makes retries idempotent and lets optimistic local rows keep their id.
- Attachments never pass through the api: the app uploads to a presigned storage url (Blob or R2) and Resend downloads from one. Vercel caps request bodies at 4.5 MB.
- A server has one owner and no accounts. The first `POST /claim` on a fresh server creates the owner and returns the owner token; private routes check its sha256 in `owner_tokens`. A claimed server only takes another claim with the host's `CLAIM_CODE`, which replaces every token. Tokens from the Better Auth days still work: the migration kept the hash of each live session's token and `authenticate` drops the signature after the dot.
- The only required env var is `DATABASE_URL`, so the deploy button needs no typing. The tracking secret is generated into `server_settings` on first boot, and the Resend key arrives from the app (`PUT /server/resend`), which also creates the server's own Resend webhook. Env values win over both, so servers from before keep their tracking secret. Migrations run in `vercel-build`, production builds only.
- Releases come from tags. Pushing `v1.2.3` runs `.github/workflows/release.yml`, which builds on the `xcode-27` runner, signs with the Developer ID certificate, notarizes and attaches `bMail-1.2.3.dmg` to a GitHub release. The version comes from the tag, not `project.yml`.
- The iPhone app ships through TestFlight from Xcode: archive the `Mail` scheme in `apps/ios` and upload it. Both apps share the bundle id `be.baree.mail`, so one App ID carries the shared Keychain group and one Google client serves both.
- Agents reach mail through `Agents`: MCP on `127.0.0.1:6245/mcp` with the bearer token from Settings, built on the official Swift SDK with a fresh SDK server per request. Each account's level (Off, Read, Organize, Ask to send, Send) is checked on every call, and an account at Off must not show up anywhere. The tools only decide; the app carries out their effects through `MailSession`, so agent actions get the same toasts, undo and send window as yours. Ask to send opens the message in the composer and posts a notification that can send it.
- On iPhone a message body is pinned to the reader's width and scaled down when it's wider (`EmailDocument.fitScript`). Pages load ahead of time while off screen, where WebKit would lay them out 980 points wide.
- AI runs on the device with the user's own key, never through the api. Tab completion keeps the gray suggestion in the editor's text (`ComposerText`) and every edit takes it back out, so `body` never holds it. Auto labelling runs after each sync pass on new inbox mail, only with labels that have a description. Descriptions are per label name and kept on the device with the rest of the AI setup, since Gmail labels have no field for one. The `labelDecisions` table remembers what it applied, so a label you take off becomes a correction in the next prompt.
- There is no shared server, and Gmail needs none. Your own domains and tracking need the api you host (README). The app gets its address from Vercel's deploy flow (`getbmail.si/connect` opens `bmail://connect?server=…`) or from you typing it, and always asks before it claims or connects.
- Fastify scoping matters: cross-cutting plugins use `fastify-plugin`, the error handler is registered before route modules and private routes live in the scope that adds the `authenticate` hook.
- The api has no build step. Locally tsx runs the TS source; on Vercel the Fastify preset compiles `app.ts` and calls its default export.
- Production api logs are plain JSON on stdout. Never add a log shipper to the code.
- Builds without an environment use `SKIP_ENV_VALIDATION=1`. Never weaken a required env var to make a build pass.
- Formatting is oxfmt's job from the repo root. Lint rules live in `@repo/oxlint-config`.
- The site's screenshots are live React replicas of the app's views with fake mail (`apps/web/components/demo`). When a view in the app changes visibly, change its replica too.

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
