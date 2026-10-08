# Mail

A native macOS mail client for Gmail, Outlook and your own domains. Gmail and Outlook sync straight from the app. Your own domains run through a small api that wraps Resend for receiving and sending, stores mail in Neon and serves per-email open and click tracking. The app is local-first: every view reads a SQLite cache and every action writes there first, so nothing in the UI waits on the network.

## This codebase

Turborepo monorepo: the macOS app (`apps/macos`, Swift), a Fastify api (`apps/api`) and shared TypeScript packages under `packages/`. The api deploys on Vercel but depends on nothing Vercel-specific: Neon for Postgres, Cloudflare R2 (S3 api) for files.

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
- **Provider** (app): one per account kind (Gmail, Outlook, your domains). Translates between its wire format and the app's models and nothing more.

## How a change flows

Contracts first, then api, then app. Change the Zod schema, implement the route against it, run `pnpm openapi` to regenerate `apps/macos/MailKit/Sources/APIClient/openapi.json`, then build the Swift package so the generated client picks it up. For breaking changes use expand-contract: shipped app builds keep calling the old shape until they update.

## Testing: when and what

Api modules are tested by injecting requests into a fully built app on PGlite (in-memory Postgres running the real migrations, triggers included) with a fake Resend gateway. Write one test per meaningful behavior of an endpoint, including the interesting rejections. Pure functions with real logic (address parsing, html instrumentation, tracking tokens) get unit tests. In Swift, test the store, the sync engine against a fake provider, mutations and serialization. No smoke tests, no tests that mock half the app.

## The macOS app

`apps/macos` is generated with XcodeGen: `project.yml` is the source of truth and `Mail.xcodeproj` is gitignored, so run `xcodegen` after pulling. Everything below the views lives in the `MailKit` Swift package and is tested with `swift test` there:

- `DesignSystem`: Vercel's tokens (colors, Geist, radii, motion), buttons, key caps, toasts. Views never hardcode a color.
- `MailCore`: the SQLite cache (GRDB + SQLiteData), `MailStore` (every write), `MailSyncEngine` (pull, push, outbox) and the provider protocol.
- `APIClient`: generated at build time from `openapi.json` by swift-openapi-generator.
- `Providers`: `ServerProvider` for your domains, `GmailProvider`, `OutlookProvider`, OAuth with PKCE and a MIME builder.

The app target holds the views, grouped by feature, plus `AppModel` (state and the one place commands run) and `Command` (the keymap that drives keys, the palette, the shortcut sheet and the menu bar).

Run it against a local api: start the api (`PORT=4317 PUBLIC_URL=http://localhost:4317 pnpm --filter api dev`), seed it once (`pnpm --filter api seed`), build, then `open "…/Baree Mail.app" --args -serverURL http://localhost:4317`. Debug builds also accept `-sessionToken <token>` and `-resetCache YES`.

## Things you need to know

- Views read with `@FetchAll`/`@Fetch` and never write. Writes go through `MailStore`, which keeps derived list columns, the search index and pending mutations consistent; a sync that races your own change replays the pending mutations on top.
- Raw GRDB SQL binds a `UUID` as a blob, but the tables store ids as lowercase text (StructuredQueries' format). Bind `uuidString.lowercased()` in raw SQL, or use the query builder.
- Gmail and Outlook ids become our ids through `UUID(stableFrom:)`, so a resync updates rows instead of duplicating them.
- OAuth client ids live in `project.yml` (`GOOGLE_CLIENT_ID`, an iOS-type Google client; `MICROSOFT_CLIENT_ID`, a public client with redirect `msauth.be.baree.mail://auth`). A provider without an id isn't offered. Sign in with Apple appears only in builds that carry its entitlement.
- Sync correctness lives in `packages/db/migrations/0001_sync_seq.sql`: `next_change` holds a row lock on the user's counter until commit, so rows commit in seq order and a cursor never skips a late commit. Every synced table needs the trigger.
- Tracked mail is instrumented only on the way out. The stored html is what was written, which is what lets the app show your own sent mail without counting an open. The app also blocks every `t.*` tracking host in its web views.
- Ids for new rows the app creates (messages, conversations, mailboxes) are generated by the app. That makes retries idempotent and lets optimistic local rows keep their id.
- Attachments never pass through the api: the app uploads to a presigned R2 url and Resend downloads from a presigned url. Vercel caps request bodies at 4.5 MB.
- Better Auth runs with the bearer plugin; the native app never has cookies. Sign-up is limited to `ALLOWED_EMAILS`, because an open sign-up would hand strangers the Resend account.
- Fastify scoping matters: cross-cutting plugins use `fastify-plugin`, the error handler is registered before route modules and private routes live in the scope that adds the `authenticate` hook.
- The api has no build step. Locally tsx runs the TS source; on Vercel the Fastify preset compiles `app.ts` and calls its default export.
- Production api logs are plain JSON on stdout. Never add a log shipper to the code.
- Builds without an environment use `SKIP_ENV_VALIDATION=1`. Never weaken a required env var to make a build pass.
- Formatting is oxfmt's job from the repo root. Lint rules live in `@repo/oxlint-config`.

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
