CREATE TABLE "conversation_labels" (
	"conversation_id" uuid NOT NULL,
	"user_id" text NOT NULL,
	"seq" bigint DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"label_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	CONSTRAINT "conversation_labels_user_id_conversation_id_pk" PRIMARY KEY("user_id","conversation_id")
);
--> statement-breakpoint
CREATE TABLE "labels" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"seq" bigint DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"name" text NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "tracked_messages" (
	"id" uuid PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"seq" bigint DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"sent_at" timestamp with time zone NOT NULL
);
--> statement-breakpoint
ALTER TABLE "events" DROP CONSTRAINT "events_message_id_messages_id_fk";
--> statement-breakpoint
ALTER TABLE "links" DROP CONSTRAINT "links_message_id_messages_id_fk";
--> statement-breakpoint
ALTER TABLE "messages" ADD COLUMN "list_unsubscribe" text;--> statement-breakpoint
ALTER TABLE "messages" ADD COLUMN "list_unsubscribe_post" text;--> statement-breakpoint
ALTER TABLE "conversation_labels" ADD CONSTRAINT "conversation_labels_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "labels" ADD CONSTRAINT "labels_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "tracked_messages" ADD CONSTRAINT "tracked_messages_user_id_user_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "conversation_labels_user_id_seq_index" ON "conversation_labels" USING btree ("user_id","seq");--> statement-breakpoint
CREATE UNIQUE INDEX "labels_user_id_name_index" ON "labels" USING btree ("user_id",lower("name")) WHERE "labels"."deleted_at" is null;--> statement-breakpoint
CREATE INDEX "labels_user_id_seq_index" ON "labels" USING btree ("user_id","seq");--> statement-breakpoint
CREATE INDEX "tracked_messages_user_id_seq_index" ON "tracked_messages" USING btree ("user_id","seq");
--> statement-breakpoint
-- Every synced table gets its seq from the trigger, see 0001_sync_seq.
CREATE TRIGGER tracked_messages_stamp_change BEFORE INSERT OR UPDATE ON tracked_messages FOR EACH ROW EXECUTE FUNCTION stamp_change();
--> statement-breakpoint
CREATE TRIGGER labels_stamp_change BEFORE INSERT OR UPDATE ON labels FOR EACH ROW EXECUTE FUNCTION stamp_change();
--> statement-breakpoint
CREATE TRIGGER conversation_labels_stamp_change BEFORE INSERT OR UPDATE ON conversation_labels FOR EACH ROW EXECUTE FUNCTION stamp_change();
