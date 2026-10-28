"use client";

import { Check, ChevronsUpDown, Layers, Paperclip, Plus, Search, Star } from "lucide-react";
import { type Dispatch, type RefObject, useEffect, useReducer, useRef, useState } from "react";

import { LogoMark } from "@/components/logo";

import { type Command, type CommandId, commandById, type Tab, tabs } from "./commands";
import { type AccountId, accounts, accountTag, type Conversation, labels } from "./data";
import { type Item, Palette, ShortcutSheet, Toasts } from "./overlays";
import { Avatar, KeyCap, MailButton, Window } from "./primitives";
import { ComposerView, ConversationView, EmptyReader } from "./reader";
import { type Action, initialState, reducer, type State, visible } from "./state";

/** Keys without modifiers, as the app's KeyboardRouter reads them. */
const plainKeys: Record<string, CommandId> = {
    j: "next",
    ArrowDown: "next",
    k: "previous",
    ArrowUp: "previous",
    e: "done",
    s: "star",
    u: "read",
    z: "undo",
    c: "compose",
    r: "reply",
    a: "replyAll",
    f: "forward",
    "/": "search",
    "?": "shortcuts",
};

const goKeys: Record<string, Tab> = { i: "inbox", s: "starred", t: "sent", e: "done", r: "tracked" };

/**
 * A working copy of bMail's main window with fake mail. While it's on screen the app's keys drive it: J and K move,
 * E files, ⌘K opens the palette. Arrow keys only count once you've clicked into it, so they still scroll the page.
 */
export function MailApp({ onCommand }: { onCommand?: (command: Command) => void }) {
    const [state, dispatch] = useReducer(reducer, initialState);
    const rootRef = useRef<HTMLDivElement>(null);
    const searchRef = useRef<HTMLInputElement>(null);
    const listRef = useRef<HTMLDivElement>(null);
    const stateRef = useRef(state);
    const onCommandRef = useRef(onCommand);
    useEffect(() => {
        stateRef.current = state;
        onCommandRef.current = onCommand;
    });

    const list = visible(state);
    const selected = state.conversations.find((c) => c.id === state.selection) ?? null;

    /** Runs a command from a key or the palette. Reads state through the ref, so it is never stale. */
    const perform = (id: CommandId) => {
        const current = stateRef.current;
        onCommandRef.current?.(commandById(id));
        const tab = tabs.find((t) => `go-${t.id}` === id);
        if (tab) return dispatch({ type: "tab", tab: tab.id });
        if (id === "search") return searchRef.current?.focus({ preventScroll: true });
        const actions: Partial<Record<CommandId, Action>> = {
            next: { type: "move", by: 1 },
            previous: { type: "move", by: -1 },
            done: { type: "file", folder: "done" },
            trash: { type: "file", folder: "trash" },
            star: { type: "star" },
            read: { type: "read" },
            undo: { type: "undo" },
            compose: { type: "compose", mode: "new" },
            reply: { type: "compose", mode: "reply" },
            replyAll: { type: "compose", mode: "reply" },
            forward: { type: "compose", mode: "forward" },
            palette: { type: "overlay", overlay: current.overlay === "palette" ? null : "palette" },
            shortcuts: { type: "overlay", overlay: current.overlay === "shortcuts" ? null : "shortcuts" },
        };
        const action = actions[id];
        if (action) dispatch(action);
    };
    const performRef = useRef(perform);
    useEffect(() => {
        performRef.current = perform;
    });

    useEffect(() => {
        const root = rootRef.current;
        if (!root) return;
        let onScreen = false;
        const observer = new IntersectionObserver(([entry]) => (onScreen = (entry?.intersectionRatio ?? 0) > 0.35), {
            threshold: [0, 0.35, 0.6],
        });
        observer.observe(root);
        let pendingGo = 0;
        const run = (id: CommandId) => performRef.current(id);

        const onKeyDown = (event: KeyboardEvent) => {
            if (!onScreen || document.documentElement.dataset.intro === "play") return;
            const current = stateRef.current;
            const target = event.target instanceof HTMLElement ? event.target : null;
            const typing = target?.closest("input, textarea") != null;
            const engaged = root.contains(document.activeElement);
            const meta = event.metaKey || event.ctrlKey;

            if (event.key === "Escape") {
                if (current.overlay) dispatch({ type: "overlay", overlay: null });
                else if (current.composer) dispatch({ type: "discard" });
                else if (typing && target === searchRef.current) dispatch({ type: "search", text: "" });
                else return;
                event.preventDefault();
                root.focus({ preventScroll: true });
                return;
            }
            if (meta && event.key.toLowerCase() === "k") {
                event.preventDefault();
                return run("palette");
            }
            if (meta && event.key === "Enter" && current.composer) {
                event.preventDefault();
                onCommandRef.current?.({ ...commandById("compose"), title: "Send", keys: ["⌘↵"] });
                dispatch({ type: "send" });
                return root.focus({ preventScroll: true });
            }
            if (typing || current.overlay) return;
            if (meta && event.key === "Backspace") {
                event.preventDefault();
                return run("trash");
            }
            if (meta || event.altKey) return;

            const tab = goKeys[event.key];
            if (tab && Date.now() - pendingGo < 1200) {
                pendingGo = 0;
                event.preventDefault();
                return run(`go-${tab}`);
            }
            if (event.key === "g") {
                pendingGo = Date.now();
                return;
            }
            const id = plainKeys[event.key];
            if (!id || (event.key.startsWith("Arrow") && !engaged)) return;
            event.preventDefault();
            run(id);
        };

        // A click anywhere in the window engages it, so arrow keys start moving the selection instead of the page.
        const onPointerDown = (event: PointerEvent) => {
            if (!(event.target instanceof HTMLElement && event.target.closest("input, textarea")))
                root.focus({ preventScroll: true });
        };

        addEventListener("keydown", onKeyDown);
        root.addEventListener("pointerdown", onPointerDown);
        return () => {
            removeEventListener("keydown", onKeyDown);
            root.removeEventListener("pointerdown", onPointerDown);
            observer.disconnect();
        };
    }, []);

    // Keeps the open row in view inside the list, without scrolling the page.
    useEffect(() => {
        const container = listRef.current;
        const row = container?.querySelector<HTMLElement>(`[data-id="${state.selection}"]`);
        if (!container || !row) return;
        if (row.offsetTop < container.scrollTop) container.scrollTop = row.offsetTop;
        else if (row.offsetTop + row.offsetHeight > container.scrollTop + container.clientHeight)
            container.scrollTop = row.offsetTop + row.offsetHeight - container.clientHeight;
    }, [state.selection]);

    const runPaletteItem = (item: Item) => {
        dispatch({ type: "overlay", overlay: null });
        rootRef.current?.focus({ preventScroll: true });
        if (item.kind === "conversation") dispatch({ type: "select", id: item.conversation.id });
        else perform(item.command.id);
    };

    return (
        <div ref={rootRef} tabIndex={-1} className="outline-none">
            <Window className="flex h-[760px] w-[1240px] flex-col">
                <TopBar state={state} dispatch={dispatch} searchRef={searchRef} />
                <TabBar state={state} dispatch={dispatch} />
                <div className="flex min-h-0 flex-1">
                    <div ref={listRef} className="relative w-[400px] shrink-0 overflow-y-auto border-r border-line">
                        {list.map((conversation) => (
                            <Row
                                key={conversation.id}
                                conversation={conversation}
                                selected={conversation.id === state.selection}
                                showTag={state.account === null}
                                onSelect={() => dispatch({ type: "select", id: conversation.id })}
                            />
                        ))}
                        {list.length === 0 && <EmptyList state={state} />}
                    </div>
                    <div className="min-w-0 flex-1">
                        {state.composer && state.composer.mode !== "reply" ? (
                            <ComposerView composer={state.composer} dispatch={dispatch} />
                        ) : selected && list.some((c) => c.id === selected.id) ? (
                            <ConversationView
                                key={selected.id}
                                conversation={selected}
                                composer={state.composer}
                                dispatch={dispatch}
                            />
                        ) : (
                            <EmptyReader />
                        )}
                    </div>
                </div>
                {state.overlay === "palette" && (
                    <Palette
                        conversations={state.conversations.filter((c) => c.folder !== "trash")}
                        hasSelection={selected !== null}
                        run={runPaletteItem}
                        close={() => dispatch({ type: "overlay", overlay: null })}
                    />
                )}
                {state.overlay === "shortcuts" && (
                    <ShortcutSheet close={() => dispatch({ type: "overlay", overlay: null })} />
                )}
                <Toasts toasts={state.toasts} dispatch={dispatch} />
            </Window>
        </div>
    );
}

function TopBar({
    state,
    dispatch,
    searchRef,
}: {
    state: State;
    dispatch: Dispatch<Action>;
    searchRef: RefObject<HTMLInputElement | null>;
}) {
    return (
        <div className="flex h-[52px] shrink-0 items-center bg-chrome pr-4 pl-[88px]">
            <LogoMark size={22} />
            <span className="mx-3 text-[18px] font-light text-line-strong">/</span>
            <AccountSwitcher current={state.account} dispatch={dispatch} />
            <span className="flex-1" />
            <label className="flex h-[30px] w-[280px] items-center gap-2 rounded-md border border-line bg-canvas pr-1.5 pl-2.5 focus-within:border-muted">
                <Search className="size-3 text-muted" />
                <input
                    ref={searchRef}
                    value={state.search}
                    onChange={(event) => dispatch({ type: "search", text: event.target.value })}
                    placeholder="Search mail"
                    aria-label="Search mail"
                    className="min-w-0 flex-1 bg-transparent outline-none placeholder:text-muted"
                />
                {!state.search && <KeyCap>/</KeyCap>}
            </label>
            <MailButton kind="primary" className="ml-3" onClick={() => dispatch({ type: "compose", mode: "new" })}>
                Compose
                <KeyCap>C</KeyCap>
            </MailButton>
            <span className="ml-3">
                <Avatar name="Mara Lindqvist" size={26} />
            </span>
        </div>
    );
}

/** Like Vercel's team switcher: every account one click away. */
function AccountSwitcher({ current, dispatch }: { current: AccountId | null; dispatch: Dispatch<Action> }) {
    const [open, setOpen] = useState(false);
    const account = accounts.find((a) => a.id === current);
    const choose = (id: AccountId | null) => {
        setOpen(false);
        dispatch({ type: "account", account: id });
    };
    return (
        <div className="relative">
            <button
                type="button"
                onClick={() => setOpen(!open)}
                className={`flex h-7 items-center gap-2 rounded-md px-1.5 font-medium ${open ? "bg-selected" : ""}`}
            >
                <AccountMark name={account?.name} />
                {account?.address ?? "All accounts"}
                <ChevronsUpDown className="size-3 text-muted" />
            </button>
            {open && (
                <div className="absolute top-9 left-0 z-30">
                    <AccountMenu current={current} onChoose={choose} />
                </div>
            )}
        </div>
    );
}

/** The switcher's menu: all accounts together, then each address, ⌘0 to ⌘9. */
export function AccountMenu({
    current,
    onChoose,
}: {
    current: AccountId | null;
    onChoose?: (account: AccountId | null) => void;
}) {
    return (
        <div className="w-[320px] rounded-lg border border-line-strong bg-raised p-1 text-[13px] text-fg shadow-[0_24px_60px_rgb(0_0_0/0.6)]">
            <AccountRow title="All accounts" keyName="⌘0" checked={!current} onClick={() => onChoose?.(null)} />
            {accounts.map((a, index) => (
                <AccountRow
                    key={a.id}
                    title={a.address}
                    name={a.name}
                    detail={a.kind === "gmail" ? "Gmail" : "Your domain"}
                    keyName={`⌘${index + 1}`}
                    checked={current === a.id}
                    onClick={() => onChoose?.(a.id)}
                />
            ))}
            <div className="my-1 h-px bg-line" />
            <div className="flex h-8 items-center gap-2.5 px-2 text-fg-2">
                <Plus className="size-5 p-[5px]" />
                Add account
            </div>
        </div>
    );
}

function AccountRow({
    title,
    name,
    detail,
    keyName,
    checked,
    onClick,
}: {
    title: string;
    name?: string;
    detail?: string;
    keyName: string;
    checked: boolean;
    onClick?: () => void;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className="flex min-h-8 w-full items-center gap-2.5 rounded px-2 py-1 text-left hover:bg-selected"
        >
            <AccountMark name={name} />
            <span className="flex flex-col">
                {title}
                {detail && <span className="text-[11.5px] text-muted">{detail}</span>}
            </span>
            <span className="min-w-4 flex-1" />
            {checked && <Check className="size-3" />}
            <KeyCap>{keyName}</KeyCap>
        </button>
    );
}

function AccountMark({ name }: { name: string | undefined }) {
    if (name) return <Avatar name={name} size={20} />;
    return (
        <span className="flex size-5 items-center justify-center rounded-full bg-selected text-fg-2">
            <Layers className="size-2.5" />
        </span>
    );
}

/** The views as text tabs, Vercel-style, with the inbox's unread count in mono. */
function TabBar({ state, dispatch }: { state: State; dispatch: Dispatch<Action> }) {
    const unread = state.conversations.filter(
        (c) => c.folder === "inbox" && c.unread && (!state.account || c.account === state.account),
    ).length;
    const searching = state.search.trim() !== "";
    return (
        <div className="flex h-[42px] shrink-0 items-end gap-[22px] border-b border-line bg-chrome px-5">
            {tabs.map((tab) => (
                <TabButton
                    key={tab.id}
                    title={tab.title}
                    count={tab.id === "inbox" ? unread : 0}
                    selected={!searching && !state.label && state.tab === tab.id}
                    onClick={() => dispatch({ type: "tab", tab: tab.id })}
                />
            ))}
            <span className="mb-3.5 h-3.5 w-px bg-line-strong" />
            {labels.map((label) => (
                <TabButton
                    key={label}
                    title={label}
                    count={0}
                    selected={!searching && state.label === label}
                    onClick={() => dispatch({ type: "label", label })}
                />
            ))}
            <span className="flex-1" />
            <span className="pb-3 font-mono text-[12px] text-muted">Updated just now</span>
        </div>
    );
}

function TabButton({
    title,
    count,
    selected,
    onClick,
}: {
    title: string;
    count: number;
    selected: boolean;
    onClick: () => void;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className={`relative flex items-baseline gap-1.5 pb-3 hover:text-fg ${selected ? "text-fg" : "text-muted"}`}
        >
            {title}
            {count > 0 && <span className="font-mono text-[12px] text-muted">{count}</span>}
            {selected && <span className="absolute inset-x-0 bottom-0 h-0.5 bg-fg" />}
        </button>
    );
}

export function Row({
    conversation: c,
    selected,
    showTag,
    onSelect,
}: {
    conversation: Conversation;
    selected: boolean;
    showTag: boolean;
    onSelect?: () => void;
}) {
    const last = c.messages.at(-1);
    return (
        <button
            type="button"
            data-id={c.id}
            tabIndex={-1}
            onClick={onSelect}
            className={`relative flex h-[62px] w-full cursor-default flex-col justify-center gap-[3px] border-b border-line/60 pr-4 pl-[30px] text-left ${selected ? "bg-selected" : "hover:bg-hover"}`}
        >
            {c.unread && <span className="absolute top-[18px] left-[13px] size-1.5 rounded-full bg-link" />}
            <div className="flex items-baseline gap-2 whitespace-nowrap">
                <span className={`truncate ${c.unread ? "font-semibold text-fg" : "font-medium text-fg-2"}`}>
                    {c.participants}
                </span>
                {c.messages.length > 1 && <span className="font-mono text-[12px] text-faint">{c.messages.length}</span>}
                <span className="min-w-2 flex-1" />
                {c.starred && <Star className="size-[9px] shrink-0 fill-warning text-warning" />}
                {c.messages.some((m) => m.attachments) && <Paperclip className="size-2.5 shrink-0 text-muted" />}
                {c.labels.length > 0 && <span className="text-[11.5px] text-fg-2">{c.labels.join(" · ")}</span>}
                {showTag && <span className="font-mono text-[11px] text-faint">{accountTag(c.account)}</span>}
                <span className="shrink-0 font-mono text-[12px] text-muted">{c.time}</span>
            </div>
            <div className="truncate">
                <span className={c.unread ? "text-fg" : "text-fg-2"}>{c.subject}</span>
                <span className="text-muted">
                    {"  "}
                    {last?.snippet}
                </span>
            </div>
        </button>
    );
}

function EmptyList({ state }: { state: State }) {
    const message = state.search
        ? "No mail matches that."
        : state.label
          ? "Nothing has this label. Add it to a conversation with L."
          : {
                inbox: "Nothing left.",
                starred: "Star a conversation with S to keep it here.",
                sent: "Mail you send shows up here.",
                done: "Conversations you mark done with E land here.",
                tracked: "Turn on tracking in the composer with ⌘⇧T.",
            }[state.tab];
    return (
        <div className="absolute inset-0 flex items-center justify-center px-8 text-center text-muted">{message}</div>
    );
}
