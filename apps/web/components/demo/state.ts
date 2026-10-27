import type { Tab } from "./commands";
import { type AccountId, type Conversation, conversations as seed, type Folder } from "./data";

/** The replica's whole state and every change to it, the way AppModel and MailStore work in the app. */

export type Composer = {
    mode: "new" | "reply" | "forward";
    /** The conversation a reply lands in. */
    conversationId: string | null;
    account: AccountId;
    to: string;
    subject: string;
    body: string;
    tracking: boolean;
};

export type Toast = {
    id: number;
    title: string;
    icon: "check" | "star" | "undo" | "send" | "trash";
    /** Shows Undo with its Z key. */
    undoable?: boolean;
    /** For "Sending in 10s": when the countdown ends. */
    sendsAt?: number;
};

/** What Z restores. A send also brings its draft back. */
type Snapshot = { conversations: Conversation[]; selection: string | null; composer?: Composer; sent?: boolean };

export type State = {
    conversations: Conversation[];
    tab: Tab;
    label: string | null;
    account: AccountId | null;
    search: string;
    selection: string | null;
    history: Snapshot[];
    toasts: Toast[];
    overlay: "palette" | "shortcuts" | null;
    composer: Composer | null;
};

export const initialState: State = {
    conversations: seed,
    tab: "inbox",
    label: null,
    account: null,
    search: "",
    selection: "kickoff",
    history: [],
    toasts: [],
    overlay: null,
    composer: null,
};

const inTab: Record<Tab, (conversation: Conversation) => boolean> = {
    inbox: (c) => c.folder === "inbox",
    starred: (c) => c.starred && c.folder !== "trash",
    sent: (c) => c.folder !== "trash" && c.messages.some((m) => m.outbound),
    done: (c) => c.folder === "done",
    tracked: (c) => c.folder !== "trash" && c.messages.some((m) => m.activity),
};

/** The list as the sidebar shows it: a query over conversations, not a folder of its own. */
export function visible(state: State): Conversation[] {
    const query = state.search.trim().toLowerCase();
    return state.conversations.filter((c) => {
        if (state.account && c.account !== state.account) return false;
        if (query) {
            const text = `${c.subject} ${c.participants} ${c.messages.map((m) => m.snippet).join(" ")}`.toLowerCase();
            return c.folder !== "trash" && text.includes(query);
        }
        if (state.label) return c.folder !== "trash" && c.labels.includes(state.label);
        return inTab[state.tab](c);
    });
}

export type Action =
    | { type: "select"; id: string | null }
    | { type: "move"; by: 1 | -1 }
    | { type: "tab"; tab: Tab }
    | { type: "label"; label: string }
    | { type: "account"; account: AccountId | null }
    | { type: "search"; text: string }
    | { type: "file"; folder: Folder }
    | { type: "star" }
    | { type: "read" }
    | { type: "undo" }
    | { type: "overlay"; overlay: State["overlay"] }
    | { type: "compose"; mode: Composer["mode"] }
    | { type: "draft"; patch: Partial<Composer> }
    | { type: "discard" }
    | { type: "send" }
    | { type: "dismiss"; toast: number };

let toastId = 0;

const withToast = (state: State, toast: Omit<Toast, "id">): Toast[] => [
    ...state.toasts.slice(-2),
    { ...toast, id: ++toastId },
];

const firstOf = (state: State) => visible(state)[0]?.id ?? null;

/** Opening a conversation reads it, like the app does. */
const open = (state: State, id: string | null): State => ({
    ...state,
    selection: id,
    conversations: state.conversations.map((c) => (c.id === id && c.unread ? { ...c, unread: false } : c)),
});

const snapshot = (state: State): Snapshot => ({ conversations: state.conversations, selection: state.selection });

/** Applies a change to the open conversation and keeps the old list for Z. */
function change(state: State, title: string, icon: Toast["icon"], update: (c: Conversation) => Conversation): State {
    return {
        ...state,
        conversations: state.conversations.map((c) => (c.id === state.selection ? update(c) : c)),
        history: [...state.history, snapshot(state)],
        toasts: withToast(state, { title, icon, undoable: true }),
    };
}

export function reducer(state: State, action: Action): State {
    switch (action.type) {
        case "select":
            return open({ ...state, composer: state.composer?.mode === "reply" ? null : state.composer }, action.id);
        case "move": {
            const list = visible(state);
            const index = list.findIndex((c) => c.id === state.selection);
            const next = list[Math.max(0, Math.min(list.length - 1, index + action.by))];
            return next ? open({ ...state, composer: null }, next.id) : state;
        }
        case "tab": {
            const next = { ...state, tab: action.tab, label: null, search: "", composer: null };
            return open(next, firstOf(next));
        }
        case "label": {
            const next = { ...state, label: action.label, search: "", composer: null };
            return open(next, firstOf(next));
        }
        case "account": {
            const next = { ...state, account: action.account };
            return open(next, firstOf(next));
        }
        case "search": {
            const next = { ...state, search: action.text };
            return { ...next, selection: firstOf(next) };
        }
        case "file": {
            const current = state.conversations.find((c) => c.id === state.selection);
            if (!current) return state;
            // Done is a toggle: E in the Done tab puts it back in the inbox.
            const folder = action.folder === "done" && current.folder === "done" ? "inbox" : action.folder;
            const list = visible(state);
            const index = list.findIndex((c) => c.id === current.id);
            const next = list[index + 1] ?? list[index - 1];
            const title = { inbox: "Moved to inbox", done: "Marked as done", trash: "Moved to trash" }[folder];
            const moved = change(state, title, "check", (c) => ({ ...c, folder }));
            return open(moved, next?.id ?? null);
        }
        case "star": {
            const current = state.conversations.find((c) => c.id === state.selection);
            if (!current) return state;
            return change(state, current.starred ? "Unstarred" : "Starred", "star", (c) => ({
                ...c,
                starred: !c.starred,
            }));
        }
        case "read": {
            const current = state.conversations.find((c) => c.id === state.selection);
            if (!current) return state;
            return change(state, current.unread ? "Marked as read" : "Marked as unread", "check", (c) => ({
                ...c,
                unread: !c.unread,
            }));
        }
        case "undo": {
            const previous = state.history.at(-1);
            if (!previous) return state;
            return {
                ...state,
                ...previous,
                composer: previous.composer ?? state.composer,
                history: state.history.slice(0, -1),
                toasts: withToast(
                    { ...state, toasts: state.toasts.filter((t) => t !== state.toasts.findLast((u) => u.undoable)) },
                    { title: previous.sent ? "Unsent" : "Undone", icon: "undo" },
                ),
            };
        }
        case "overlay":
            return { ...state, overlay: action.overlay };
        case "compose": {
            const current = state.conversations.find((c) => c.id === state.selection);
            if (action.mode !== "new" && !current) return state;
            const last = current?.messages.at(-1);
            const sender = last?.outbound ? last.to[0] : last?.from;
            return {
                ...state,
                overlay: null,
                composer: {
                    mode: action.mode,
                    conversationId: action.mode === "reply" ? (current?.id ?? null) : null,
                    account: current?.account ?? state.account ?? "mara",
                    to: action.mode === "reply" ? (sender?.name ?? "") : "",
                    subject: action.mode === "forward" ? `Fwd: ${current?.subject ?? ""}` : "",
                    body: "",
                    tracking: false,
                },
            };
        }
        case "draft":
            return state.composer ? { ...state, composer: { ...state.composer, ...action.patch } } : state;
        case "discard": {
            const draft = state.composer;
            if (!draft) return state;
            // Like the app: a composer with something typed comes back with Undo.
            const typed =
                draft.body.trim() !== "" ||
                (draft.mode === "new" && (draft.to.trim() !== "" || draft.subject.trim() !== ""));
            if (!typed) return { ...state, composer: null };
            return {
                ...state,
                composer: null,
                history: [...state.history, { ...snapshot(state), composer: draft }],
                toasts: withToast(state, { title: "Discarded", icon: "trash", undoable: true }),
            };
        }
        case "send": {
            const draft = state.composer;
            if (!draft) return state;
            const to = draft.to.trim() || "Priya Raman";
            const message = {
                id: `sent-${++toastId}`,
                from: { name: "Mara Lindqvist", email: "mara@northwind.studio" },
                to: [{ name: to, email: "" }],
                outbound: true,
                time: "10:31 AM",
                snippet: draft.body.trim() || "(no text)",
                body: draft.body.trim() ? draft.body.trim().split(/\n+/) : ["(no text)"],
                delivery: "Sent" as const,
                activity: draft.tracking ? { events: [], links: [] } : undefined,
            };
            const reply = draft.mode === "reply" ? draft.conversationId : null;
            const conversations: Conversation[] = reply
                ? state.conversations.map((c) =>
                      c.id === reply ? { ...c, time: message.time, messages: [...c.messages, message] } : c,
                  )
                : [
                      {
                          id: message.id,
                          account: draft.account,
                          subject: draft.subject.trim() || "(no subject)",
                          participants: to,
                          time: message.time,
                          folder: "done",
                          unread: false,
                          starred: false,
                          labels: [],
                          messages: [message],
                      },
                      ...state.conversations,
                  ];
            return {
                ...state,
                conversations,
                composer: null,
                selection: reply ?? state.selection,
                history: [...state.history, { ...snapshot(state), composer: draft, sent: true }],
                toasts: withToast(state, {
                    title: "Sending in",
                    icon: "send",
                    undoable: true,
                    sendsAt: Date.now() + 10_000,
                }),
            };
        }
        case "dismiss":
            return { ...state, toasts: state.toasts.filter((t) => t.id !== action.toast) };
    }
}
