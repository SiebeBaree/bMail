import {
    Activity,
    ArrowDown,
    ArrowLeft,
    ArrowUp,
    BellOff,
    Check,
    CircleCheck,
    Command as CommandIcon,
    Forward,
    Inbox,
    Keyboard,
    ListChecks,
    type LucideIcon,
    OctagonAlert,
    Reply,
    ReplyAll,
    Search,
    Send,
    Settings,
    SquarePen,
    Star,
    Tag,
    Trash2,
    Undo2,
    CircleDot,
} from "lucide-react";

/** The app's one keymap (App/Commands/Command.swift), for the palette, the shortcut sheet and the keyboard. */

export type Tab = "inbox" | "starred" | "sent" | "done" | "tracked";

export const tabs = [
    { id: "inbox", title: "Inbox", key: "I", icon: Inbox },
    { id: "starred", title: "Starred", key: "S", icon: Star },
    { id: "sent", title: "Sent", key: "T", icon: Send },
    { id: "done", title: "Done", key: "E", icon: Check },
    { id: "tracked", title: "Tracked", key: "R", icon: Activity },
] as const satisfies readonly { id: Tab; title: string; key: string; icon: LucideIcon }[];

export type Group = "Move" | "Triage" | "Write" | "App";

export type Command = {
    id: string;
    title: string;
    icon: LucideIcon;
    keys: readonly string[];
    group: Group;
    /** Acts on the open conversation, so the palette hides it when nothing is open. */
    needsConversation?: boolean;
    /** The replica can run it. The sheet still lists the rest. */
    demo?: boolean;
    /** A one-word name for the keyboard section's keycaps. */
    short?: string;
};

const definitions = [
    { id: "next", title: "Next conversation", icon: ArrowDown, keys: ["J"], group: "Move", demo: true, short: "Next" },
    {
        id: "previous",
        title: "Previous conversation",
        icon: ArrowUp,
        keys: ["K"],
        group: "Move",
        demo: true,
        short: "Previous",
    },
    { id: "back", title: "Back", icon: ArrowLeft, keys: ["Esc"], group: "Move" },
    ...tabs.map((tab) => ({
        id: `go-${tab.id}` as const,
        title: `Go to ${tab.title}`,
        icon: tab.icon,
        keys: ["G", tab.key] as const,
        group: "Move" as const,
        demo: true,
    })),
    { id: "allAccounts", title: "All accounts", icon: CircleDot, keys: ["⌘0"], group: "Move" },
    { id: "account", title: "Account 1", icon: CircleDot, keys: ["⌘1"], group: "Move" },
    { id: "search", title: "Search", icon: Search, keys: ["/"], group: "Move", demo: true, short: "Search" },
    {
        id: "check",
        title: "Select conversation",
        icon: CircleCheck,
        keys: ["X"],
        group: "Triage",
        needsConversation: true,
        short: "Select",
    },
    { id: "extendNext", title: "Select next too", icon: CircleCheck, keys: ["⇧J"], group: "Triage" },
    { id: "extendPrevious", title: "Select previous too", icon: CircleCheck, keys: ["⇧K"], group: "Triage" },
    { id: "checkAll", title: "Select all", icon: ListChecks, keys: ["⌘A"], group: "Triage" },
    {
        id: "done",
        title: "Mark as done",
        icon: Check,
        keys: ["E"],
        group: "Triage",
        needsConversation: true,
        demo: true,
        short: "Done",
    },
    {
        id: "trash",
        title: "Move to trash",
        icon: Trash2,
        keys: ["⌘⌫"],
        group: "Triage",
        needsConversation: true,
        demo: true,
    },
    {
        id: "spam",
        title: "Report spam",
        icon: OctagonAlert,
        keys: ["!"],
        group: "Triage",
        needsConversation: true,
        short: "Spam",
    },
    {
        id: "star",
        title: "Star",
        icon: Star,
        keys: ["S"],
        group: "Triage",
        needsConversation: true,
        demo: true,
        short: "Star",
    },
    {
        id: "read",
        title: "Mark read or unread",
        icon: CircleDot,
        keys: ["U"],
        group: "Triage",
        needsConversation: true,
        demo: true,
        short: "Unread",
    },
    { id: "label", title: "Label", icon: Tag, keys: ["L"], group: "Triage", needsConversation: true, short: "Label" },
    { id: "unsubscribe", title: "Unsubscribe", icon: BellOff, keys: [], group: "Triage", needsConversation: true },
    { id: "undo", title: "Undo", icon: Undo2, keys: ["Z"], group: "Triage", demo: true, short: "Undo" },
    { id: "compose", title: "New message", icon: SquarePen, keys: ["C"], group: "Write", demo: true, short: "Compose" },
    {
        id: "reply",
        title: "Reply",
        icon: Reply,
        keys: ["R"],
        group: "Write",
        needsConversation: true,
        demo: true,
        short: "Reply",
    },
    {
        id: "replyAll",
        title: "Reply all",
        icon: ReplyAll,
        keys: ["A"],
        group: "Write",
        needsConversation: true,
        demo: true,
        short: "All",
    },
    {
        id: "forward",
        title: "Forward",
        icon: Forward,
        keys: ["F"],
        group: "Write",
        needsConversation: true,
        demo: true,
        short: "Forward",
    },
    { id: "palette", title: "Command palette", icon: CommandIcon, keys: ["⌘K"], group: "App", demo: true },
    {
        id: "shortcuts",
        title: "Keyboard shortcuts",
        icon: Keyboard,
        keys: ["?"],
        group: "App",
        demo: true,
        short: "Help",
    },
    { id: "settings", title: "Settings", icon: Settings, keys: ["⌘,"], group: "App" },
] as const satisfies readonly Command[];

export type CommandId = (typeof definitions)[number]["id"];
export type AppCommand = Command & { id: CommandId };

/** Every command, typed loosely enough to read optional fields but with ids the compiler knows. */
export const commands: readonly AppCommand[] = definitions;

export const commandById = (id: CommandId): AppCommand =>
    commands.find((command) => command.id === id) ?? definitions[0];

/** Subsequence matching that prefers prefixes and word starts, so "rep" finds Reply before Report spam. */
export function fuzzyScore(query: string, text: string): number | null {
    const q = query.toLowerCase();
    const t = text.toLowerCase();
    if (!q) return 0;
    if (t.startsWith(q)) return 100;
    if (t.includes(` ${q}`)) return 80;
    if (t.includes(q)) return 60;
    let index = 0;
    for (const character of q) {
        const found = t.indexOf(character, index);
        if (found === -1) return null;
        index = found + 1;
    }
    return 20;
}
