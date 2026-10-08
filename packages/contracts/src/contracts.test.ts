import { describe, expect, it } from "vitest";

import { updateConversationSchema } from "./conversations";
import { createDomainSchema } from "./domains";
import { createMailboxSchema } from "./mailboxes";
import { sendMessageSchema } from "./messages";

const id = "8f14e45f-ceea-4b67-8a55-6a86e93ac3e1";

describe("createDomainSchema", () => {
    it("normalizes what people paste", () => {
        expect(createDomainSchema.parse({ name: "  Baree.BE " })).toEqual({ name: "baree.be" });
    });

    it.each(["baree", "https://baree.be", "siebe@baree.be", "-baree.be", "baree..be"])("rejects %s", (name) => {
        expect(createDomainSchema.safeParse({ name }).success).toBe(false);
    });
});

describe("createMailboxSchema", () => {
    const base = { id: id, domainId: id, displayName: "Siebe" };

    it("lowercases the local part", () => {
        expect(createMailboxSchema.parse({ ...base, localPart: "Hello" }).localPart).toBe("hello");
    });

    it.each(["", "with space", "a@b", ".dot"])("rejects %j", (localPart) => {
        expect(createMailboxSchema.safeParse({ ...base, localPart }).success).toBe(false);
    });
});

describe("updateConversationSchema", () => {
    it("rejects an update that changes nothing", () => {
        expect(updateConversationSchema.safeParse({}).success).toBe(false);
    });
});

describe("sendMessageSchema", () => {
    it("defaults to no tracking, no copies and no attachments", () => {
        const parsed = sendMessageSchema.parse({
            id: id,
            conversationId: id,
            mailboxId: id,
            to: [{ email: "jan@wouters.be" }],
            subject: "Hi",
            html: "<p>Hi</p>",
            text: "Hi",
        });
        expect(parsed).toMatchObject({ trackingEnabled: false, cc: [], bcc: [], attachmentIds: [] });
    });

    it("rejects a mail without recipients", () => {
        const result = sendMessageSchema.safeParse({
            id: id,
            conversationId: id,
            mailboxId: id,
            to: [],
            subject: "Hi",
            html: "",
            text: "",
        });
        expect(result.error?.issues[0]?.message).toBe("Add at least one recipient.");
    });
});
