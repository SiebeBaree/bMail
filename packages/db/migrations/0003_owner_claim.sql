CREATE TABLE "owner_tokens" (
	"token_hash" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "server_settings" (
	"id" smallint PRIMARY KEY DEFAULT 1 NOT NULL,
	"tracking_secret" text,
	"resend_api_key" text,
	"resend_webhook_id" text,
	"resend_webhook_secret" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "server_settings_single_row" CHECK (id = 1)
);
--> statement-breakpoint
-- Better Auth sessions still in use become owner tokens, so devices signed in before the claim stay signed in. The app
-- sends Better Auth's `token.signature`; the authenticate hook hashes the part before the dot.
INSERT INTO "owner_tokens" ("token_hash", "user_id")
SELECT encode(sha256(convert_to("token", 'UTF8')), 'hex'), "user_id" FROM "session" WHERE "expires_at" > now();
--> statement-breakpoint
ALTER TABLE "account" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "session" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
ALTER TABLE "verification" DISABLE ROW LEVEL SECURITY;--> statement-breakpoint
DROP TABLE "account" CASCADE;--> statement-breakpoint
DROP TABLE "session" CASCADE;--> statement-breakpoint
DROP TABLE "verification" CASCADE;--> statement-breakpoint
ALTER TABLE "user" DROP CONSTRAINT "user_email_unique";--> statement-breakpoint
ALTER TABLE "owner_tokens" ADD CONSTRAINT "owner_tokens_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "owner_tokens_user_id_index" ON "owner_tokens" USING btree ("user_id");--> statement-breakpoint
ALTER TABLE "user" DROP COLUMN "name";--> statement-breakpoint
ALTER TABLE "user" DROP COLUMN "email";--> statement-breakpoint
ALTER TABLE "user" DROP COLUMN "email_verified";--> statement-breakpoint
ALTER TABLE "user" DROP COLUMN "image";--> statement-breakpoint
ALTER TABLE "user" DROP COLUMN "updated_at";