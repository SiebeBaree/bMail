"use client";

import { Check, Mail, Search, Send, Star, Undo2 } from "lucide-react";
import { AnimatePresence, motion } from "motion/react";
import { type Dispatch, type ReactNode, useEffect, useMemo, useState } from "react";

import { type AppCommand, commands, fuzzyScore, type Group } from "./commands";
import type { Conversation } from "./data";
import { KeyCap, Keys, MailButton } from "./primitives";
import type { Action, Toast } from "./state";

const enter = { type: "spring", duration: 0.18, bounce: 0.08 } as const;

export type Item = { kind: "command"; command: AppCommand } | { kind: "conversation"; conversation: Conversation };

/** ⌘K (App/Palette/CommandPalette.swift). Commands and conversations in one list, every command with its key. */
export function Palette({
    conversations,
    hasSelection,
    run,
    close,
}: {
    conversations: Conversation[];
    hasSelection: boolean;
    run: (item: Item) => void;
    close: () => void;
}) {
    const [query, setQuery] = useState("");
    const [highlighted, setHighlighted] = useState(0);

    const items = useMemo((): Item[] => {
        const ranked = commands
            .filter((command) => command.demo && command.id !== "palette")
            .filter((command) => !command.needsConversation || hasSelection)
            .flatMap((command) => {
                const score = fuzzyScore(query, command.title);
                // Among equals the shorter title wins, so "rep" lands on Reply.
                return score === null ? [] : [{ command, score: score - command.title.length * 0.01 }];
            })
            .toSorted((a, b) => b.score - a.score)
            .map(({ command }): Item => ({ kind: "command", command }));
        const found =
            query.length < 2
                ? []
                : conversations
                      .filter((c) => `${c.subject} ${c.participants}`.toLowerCase().includes(query.toLowerCase()))
                      .slice(0, 6)
                      .map((conversation): Item => ({ kind: "conversation", conversation }));
        return [...ranked, ...found];
    }, [query, conversations, hasSelection]);

    return (
        <Backdrop close={close}>
            <motion.div
                initial={{ opacity: 0, y: -6, scale: 0.98 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                transition={enter}
                className="mx-auto mt-24 w-[640px] overflow-hidden rounded-xl border border-line-strong bg-raised shadow-[0_16px_60px_rgb(0_0_0/0.45)]"
                onClick={(event) => event.stopPropagation()}
            >
                <div className="flex h-[52px] items-center gap-2.5 border-b border-line px-4">
                    <Search className="size-4 text-muted" />
                    <input
                        // The palette exists to be typed into the moment it opens.
                        // oxlint-disable-next-line jsx-a11y/no-autofocus
                        autoFocus
                        value={query}
                        placeholder="Type a command or search"
                        aria-label="Command"
                        onChange={(event) => {
                            setQuery(event.target.value);
                            setHighlighted(0);
                        }}
                        onKeyDown={(event) => {
                            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
                                event.preventDefault();
                                const step = event.key === "ArrowDown" ? 1 : -1;
                                setHighlighted((index) => (index + step + items.length) % Math.max(1, items.length));
                            } else if (event.key === "Enter") {
                                const item = items[highlighted];
                                if (item) run(item);
                            }
                        }}
                        className="flex-1 bg-transparent text-[15px] outline-none placeholder:text-muted"
                    />
                </div>
                <div className="max-h-[360px] overflow-y-auto">
                    {items.map((item, index) => (
                        <PaletteRow
                            key={item.kind === "command" ? item.command.id : item.conversation.id}
                            item={item}
                            query={query}
                            highlighted={index === highlighted}
                            onHover={() => setHighlighted(index)}
                            onRun={() => run(item)}
                        />
                    ))}
                    {items.length === 0 && <div className="flex h-10 items-center px-4 text-muted">No matches</div>}
                </div>
                <div className="flex h-9 items-center gap-4 border-t border-line px-4 text-[12px] text-muted">
                    <span className="flex items-center gap-1.5">
                        <KeyCap>↑</KeyCap>
                        <KeyCap>↓</KeyCap>
                        Move
                    </span>
                    <span className="flex items-center gap-1.5">
                        <KeyCap>↵</KeyCap>
                        Run
                    </span>
                    <span className="flex items-center gap-1.5">
                        <KeyCap>Esc</KeyCap>
                        Close
                    </span>
                </div>
            </motion.div>
        </Backdrop>
    );
}

function PaletteRow({
    item,
    query,
    highlighted,
    onHover,
    onRun,
}: {
    item: Item;
    query: string;
    highlighted: boolean;
    onHover: () => void;
    onRun: () => void;
}) {
    const Icon = item.kind === "command" ? item.command.icon : Mail;
    const title = item.kind === "command" ? item.command.title : item.conversation.subject;
    return (
        <button
            type="button"
            onMouseMove={onHover}
            onClick={onRun}
            className={`flex h-10 w-full items-center gap-3 px-4 text-left ${highlighted ? "bg-selected text-fg" : "text-fg-2"}`}
        >
            <Icon className={`size-[13px] shrink-0 ${highlighted ? "text-fg" : "text-muted"}`} />
            <Highlighted text={title} query={query} />
            <span className="flex-1" />
            {item.kind === "command" ? (
                <Keys keys={item.command.keys} />
            ) : (
                <span className="truncate text-[12px] text-muted">
                    {item.conversation.participants} · {item.conversation.time}
                </span>
            )}
        </button>
    );
}

function Highlighted({ text, query }: { text: string; query: string }) {
    const start = query ? text.toLowerCase().indexOf(query.toLowerCase()) : -1;
    if (start === -1) return <span className="truncate">{text}</span>;
    return (
        <span className="truncate">
            {text.slice(0, start)}
            <span className="font-semibold text-fg">{text.slice(start, start + query.length)}</span>
            {text.slice(start + query.length)}
        </span>
    );
}

const groups: Group[] = ["Move", "Triage", "Write", "App"];

/** `?` (App/Palette/ShortcutSheet.swift). Every shortcut, grouped, from the same keymap the keys use. */
export function ShortcutSheet({ close }: { close: () => void }) {
    return (
        <Backdrop close={close} center>
            <motion.div
                initial={{ opacity: 0, scale: 0.98 }}
                animate={{ opacity: 1, scale: 1 }}
                transition={enter}
                className="flex flex-col gap-5 rounded-xl border border-line-strong bg-raised p-7 shadow-[0_16px_60px_rgb(0_0_0/0.45)]"
                onClick={(event) => event.stopPropagation()}
            >
                <div className="flex items-center justify-between">
                    <span className="text-[16px] font-semibold">Keyboard shortcuts</span>
                    <KeyCap>Esc</KeyCap>
                </div>
                <div className="flex gap-9">
                    {groups.map((group) => (
                        <div key={group} className="flex w-[230px] flex-col gap-2">
                            <span className="pb-1 font-semibold">{group}</span>
                            {commands
                                .filter((command) => command.group === group && command.id !== "extendPrevious")
                                .map((command) => (
                                    <div key={command.id} className="flex items-center justify-between gap-4">
                                        <span className="truncate text-fg-2">{command.title}</span>
                                        <Keys keys={command.keys} />
                                    </div>
                                ))}
                        </div>
                    ))}
                </div>
            </motion.div>
        </Backdrop>
    );
}

function Backdrop({ children, close, center }: { children: ReactNode; close: () => void; center?: boolean }) {
    return (
        <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ duration: 0.12 }}
            onClick={close}
            className={`absolute inset-0 z-20 bg-black/35 ${center ? "flex items-center justify-center" : ""}`}
        >
            {children}
        </motion.div>
    );
}

const toastIcons = { check: Check, star: Star, undo: Undo2, send: Send } as const;

/** Bottom-left toasts (DesignSystem/Toasts.swift): what just happened, with Undo when it can be undone. */
export function Toasts({ toasts, dispatch }: { toasts: Toast[]; dispatch: Dispatch<Action> }) {
    return (
        <div className="pointer-events-none absolute bottom-5 left-5 z-30 flex flex-col gap-2">
            <AnimatePresence initial={false}>
                {toasts.map((toast) => (
                    <motion.div
                        key={toast.id}
                        layout
                        initial={{ opacity: 0, y: 16 }}
                        animate={{ opacity: 1, y: 0 }}
                        exit={{ opacity: 0, y: 8 }}
                        transition={enter}
                        className="pointer-events-auto"
                    >
                        <ToastView toast={toast} dispatch={dispatch} />
                    </motion.div>
                ))}
            </AnimatePresence>
        </div>
    );
}

function ToastView({ toast, dispatch }: { toast: Toast; dispatch: Dispatch<Action> }) {
    const Icon = toastIcons[toast.icon];
    const remaining = useCountdown(toast.sendsAt);

    useEffect(() => {
        const lifetime = toast.sendsAt ? toast.sendsAt - Date.now() : 5000;
        const timer = setTimeout(() => dispatch({ type: "dismiss", toast: toast.id }), lifetime);
        return () => clearTimeout(timer);
    }, [toast, dispatch]);

    return (
        <div className="flex min-h-[46px] w-[400px] items-center gap-2.5 rounded-lg border border-line-strong bg-raised py-2 pr-2 pl-3.5 shadow-[0_8px_32px_rgb(0_0_0/0.35)]">
            <Icon className="size-[13px] shrink-0 text-fg-2" />
            <span className="flex-1">{toast.sendsAt ? `${toast.title} ${remaining}s` : toast.title}</span>
            {toast.undoable && (
                <MailButton kind="secondary" className="h-[26px] px-2.5" onClick={() => dispatch({ type: "undo" })}>
                    Undo
                    <KeyCap>Z</KeyCap>
                </MailButton>
            )}
        </div>
    );
}

/** Whole seconds until `until`, ticking once a second while there is one. */
function useCountdown(until: number | undefined) {
    const [now, setNow] = useState(() => Date.now());
    useEffect(() => {
        if (!until) return;
        const timer = setInterval(() => setNow(Date.now()), 1000);
        return () => clearInterval(timer);
    }, [until]);
    return until ? Math.max(1, Math.ceil((until - now) / 1000)) : 0;
}
