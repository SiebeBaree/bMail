"use client";

import type { Conversation } from "./data";
import { ConversationView } from "./reader";

/** An open conversation for a screenshot: the real reader, with nothing to dispatch to. */
export function StaticConversation({ conversation }: { conversation: Conversation }) {
    return <ConversationView conversation={conversation} composer={null} dispatch={() => {}} />;
}
