-- Sync cursor. Every synced row gets the next number from its user's counter on each insert and update. The upsert
-- holds a row lock on the counter until the transaction commits, which serializes writers per user: rows commit in
-- seq order and the app's cursor can never step over a row that commits late.
CREATE FUNCTION next_change(uid text) RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO sync_state (user_id, seq) VALUES (uid, 1)
    ON CONFLICT (user_id) DO UPDATE SET seq = sync_state.seq + 1
    RETURNING seq
$$;
--> statement-breakpoint
CREATE FUNCTION stamp_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.seq := next_change(NEW.user_id);
    RETURN NEW;
END
$$;
--> statement-breakpoint
CREATE TRIGGER domains_stamp_change BEFORE INSERT OR UPDATE ON domains FOR EACH ROW EXECUTE FUNCTION stamp_change();
--> statement-breakpoint
CREATE TRIGGER mailboxes_stamp_change BEFORE INSERT OR UPDATE ON mailboxes FOR EACH ROW EXECUTE FUNCTION stamp_change();
--> statement-breakpoint
CREATE TRIGGER conversations_stamp_change BEFORE INSERT OR UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION stamp_change();
--> statement-breakpoint
CREATE TRIGGER messages_stamp_change BEFORE INSERT OR UPDATE ON messages FOR EACH ROW EXECUTE FUNCTION stamp_change();
--> statement-breakpoint
CREATE TRIGGER events_stamp_change BEFORE INSERT OR UPDATE ON events FOR EACH ROW EXECUTE FUNCTION stamp_change();
