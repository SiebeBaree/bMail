"use client";

import { ChevronDown, CircleCheck, FileText, Mail, Paperclip, Reply, Star, Tag, Trash2 } from "lucide-react";
import { type Dispatch, type ReactNode, useEffect, useRef, useState } from "react";

import { Activity } from "./activity";
import { accountById, type Conversation, type Message } from "./data";
import { Avatar, KeyCap, MailButton, StatusDot, Switch } from "./primitives";
import type { Action, Composer } from "./state";

/** The open conversation (App/Reader/ConversationView.swift). Newest message open, older ones folded. */
export function ConversationView({
    conversation,
    composer,
    dispatch,
}: {
    conversation: Conversation;
    composer: Composer | null;
    dispatch: Dispatch<Action>;
}) {
    const [expanded, setExpanded] = useState(() => new Set(conversation.messages.slice(-1).map((m) => m.id)));
    const last = conversation.messages.at(-1);
    const replying = composer?.mode === "reply" && composer.conversationId === conversation.id;
    const scrollRef = useRef<HTMLDivElement>(null);
    // A reply opens under the thread, so bring it into view.
    useEffect(() => {
        if (replying && scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }, [replying]);
    const toggle = (id: string) =>
        setExpanded((current) => {
            const next = new Set(current);
            if (!next.delete(id)) next.add(id);
            return next;
        });

    return (
        <div className="flex h-full flex-col bg-canvas">
            <div className="flex h-12 shrink-0 items-center gap-1 border-b border-line pr-4 pl-8">
                <Mail className="size-[11px] text-muted" />
                <span className="ml-1 font-mono text-[12px] text-muted">
                    {accountById(conversation.account).address}
                </span>
                {conversation.labels.length > 0 && (
                    <span className="ml-3.5 flex items-center gap-2">
                        <Tag className="size-[11px] text-muted" />
                        {conversation.labels.map((label) => (
                            <button
                                key={label}
                                type="button"
                                onClick={() => dispatch({ type: "label", label })}
                                className="text-[12px] text-fg-2 hover:text-fg"
                            >
                                {label}
                            </button>
                        ))}
                    </span>
                )}
                <span className="flex-1" />
                {conversation.unsubscribe && <MailButton kind="ghost">Unsubscribe</MailButton>}
                <ActionButton icon={<Tag className="size-3" />} keyName="L" />
                <ActionButton
                    icon={<CircleCheck className="size-3" />}
                    keyName="E"
                    onClick={() => dispatch({ type: "file", folder: "done" })}
                />
                <ActionButton
                    icon={<Star className={`size-3 ${conversation.starred ? "fill-current" : ""}`} />}
                    keyName="S"
                    onClick={() => dispatch({ type: "star" })}
                />
                <ActionButton
                    icon={<Trash2 className="size-3" />}
                    keyName="⌘⌫"
                    onClick={() => dispatch({ type: "file", folder: "trash" })}
                />
            </div>
            <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto px-8 pt-[26px] pb-6">
                <p className="text-[20px] font-semibold tracking-[-0.3px]">{conversation.subject}</p>
                {/* One message names its sender right below, so only a thread gets the line. */}
                {conversation.messages.length > 1 ? (
                    <p className="mt-1 mb-[18px] text-[12px] text-muted">{summary(conversation)}</p>
                ) : (
                    <div className="mb-[18px]" />
                )}
                {conversation.messages.map((message) => (
                    <div key={message.id} className="border-t border-line">
                        {expanded.has(message.id) ? (
                            <MessageView message={message} collapse={() => toggle(message.id)} />
                        ) : (
                            <CollapsedMessage message={message} open={() => toggle(message.id)} />
                        )}
                    </div>
                ))}
                {replying && (
                    <div className="mt-4">
                        <ComposerView composer={composer} dispatch={dispatch} inline />
                    </div>
                )}
            </div>
            {!composer && last && (
                <div className="shrink-0 px-8 py-3.5">
                    <div className="flex h-11 w-full items-center gap-0.5 rounded-lg border border-line-strong pr-1.5">
                        <button
                            type="button"
                            onClick={() => dispatch({ type: "compose", mode: "reply" })}
                            className="flex h-full flex-1 items-center gap-2.5 pr-1.5 pl-3.5 text-muted hover:text-fg"
                        >
                            <Reply className="size-3" />
                            Reply to {last.outbound ? (last.to[0]?.name ?? "everyone") : last.from.name}
                            <span className="flex-1" />
                            <KeyCap>R</KeyCap>
                        </button>
                        <MailButton kind="ghost" className="gap-2">
                            Reply all <KeyCap>A</KeyCap>
                        </MailButton>
                        <MailButton kind="ghost" className="gap-2">
                            Forward <KeyCap>F</KeyCap>
                        </MailButton>
                    </div>
                </div>
            )}
        </div>
    );
}

function summary(conversation: Conversation) {
    const { messages } = conversation;
    const others = [...new Set(messages.filter((m) => !m.outbound).map((m) => m.from.name))];
    const people = others.length > 0 ? others.join(" and ") : (messages[0]?.to.map((p) => p.name).join(", ") ?? "");
    return `${messages.length} messages with ${people}`;
}

function ActionButton({ icon, keyName, onClick }: { icon: ReactNode; keyName: string; onClick?: () => void }) {
    return (
        <MailButton kind="ghost" onClick={onClick} className="gap-1.5">
            {icon}
            <KeyCap>{keyName}</KeyCap>
        </MailButton>
    );
}

function MessageView({ message, collapse }: { message: Message; collapse: () => void }) {
    return (
        <div className="flex flex-col gap-3.5 py-4">
            <button type="button" onClick={collapse} className="flex items-start gap-3 text-left">
                <Avatar name={message.from.name} />
                <span className="flex min-w-0 flex-col gap-0.5">
                    <span className="flex gap-1.5">
                        <span className="font-semibold">{message.outbound ? "You" : message.from.name}</span>
                        <span className="text-muted">{message.from.email}</span>
                    </span>
                    <span className="truncate text-[12px] text-muted">
                        to {message.outbound ? message.to.map((p) => p.name).join(", ") : "you"}
                    </span>
                </span>
                <span className="flex-1" />
                {message.outbound && message.delivery && (
                    <span className="flex items-center gap-1.5 text-[12px] text-muted">
                        <StatusDot tone={message.delivery === "Delivered" ? "success" : "muted"} />
                        {message.delivery}
                    </span>
                )}
                <span className="pl-3 font-mono text-[12px] text-muted">{message.time}</span>
            </button>
            <div className="flex flex-col gap-3.5 pl-10 text-[14px] leading-[1.55] text-fg">
                {message.body.map((paragraph) => (
                    <p key={paragraph}>{paragraph}</p>
                ))}
            </div>
            {message.attachments && (
                <div className="flex gap-2 pl-10">
                    {message.attachments.map((file) => (
                        <span
                            key={file.name}
                            className="flex h-8 items-center gap-2 rounded-md border border-line-strong px-2.5"
                        >
                            <FileText className="size-3 text-muted" />
                            {file.name}
                            <span className="font-mono text-[12px] text-muted">{file.size}</span>
                        </span>
                    ))}
                </div>
            )}
            {message.outbound && message.activity && message.activity.events.length > 0 && (
                <div className="pt-1.5 pl-10">
                    <Activity activity={message.activity} />
                </div>
            )}
        </div>
    );
}

function CollapsedMessage({ message, open }: { message: Message; open: () => void }) {
    return (
        <button
            type="button"
            onClick={open}
            className="flex w-full items-center gap-3 py-[11px] text-left hover:bg-hover/60"
        >
            <Avatar name={message.from.name} size={22} />
            <span className="w-[120px] shrink-0 truncate font-medium text-fg-2">
                {message.outbound ? "You" : message.from.name}
            </span>
            <span className="min-w-0 flex-1 truncate text-muted">{message.snippet}</span>
            <span className="font-mono text-[12px] text-muted">{message.time}</span>
        </button>
    );
}

const composerTitles = { new: "New message", forward: "Forward", reply: "Reply" } as const;

/** The composer (App/Composer/ComposerView.swift). New mail takes the reader's place; a reply sits under the thread. */
export function ComposerView({
    composer,
    dispatch,
    inline = false,
}: {
    composer: Composer;
    dispatch: Dispatch<Action>;
    inline?: boolean;
}) {
    const toRef = useRef<HTMLInputElement>(null);
    const bodyRef = useRef<HTMLTextAreaElement>(null);
    // Where the cursor starts: the body when there's already someone to write to, not as the draft changes.
    const [startsInBody] = useState(composer.to !== "");
    const account = accountById(composer.account);
    const patch = (value: Partial<Composer>) => dispatch({ type: "draft", patch: value });

    useEffect(() => {
        (startsInBody ? bodyRef : toRef).current?.focus({ preventScroll: true });
    }, [startsInBody]);

    return (
        <div className={`flex flex-col bg-canvas ${inline ? "rounded-lg border border-line-strong" : "h-full"}`}>
            {!inline && (
                <div className="flex h-12 shrink-0 items-center gap-2 border-b border-line px-5">
                    <span className="font-semibold">{composerTitles[composer.mode]}</span>
                    <span className="flex-1" />
                    <DiscardButton dispatch={dispatch} />
                </div>
            )}
            <Field label="From">
                <span className="flex h-[26px] items-center gap-2 rounded-md border border-line-strong px-2.5">
                    {account.name} &lt;{account.address}&gt;
                    <ChevronDown className="size-3 text-muted" />
                </span>
                <span className="flex-1" />
                <MailButton kind="ghost">Cc Bcc</MailButton>
            </Field>
            <Field label="To">
                <input
                    ref={toRef}
                    value={composer.to}
                    onChange={(event) => patch({ to: event.target.value })}
                    aria-label="To"
                    className="flex-1 bg-transparent outline-none"
                />
            </Field>
            {composer.mode !== "reply" && (
                <Field label="Subject">
                    <input
                        value={composer.subject}
                        onChange={(event) => patch({ subject: event.target.value })}
                        aria-label="Subject"
                        className="flex-1 bg-transparent outline-none"
                    />
                </Field>
            )}
            <textarea
                ref={bodyRef}
                value={composer.body}
                onChange={(event) => patch({ body: event.target.value })}
                aria-label="Message"
                placeholder="Write something, then ⌘↵"
                className={`resize-none bg-transparent px-5 pt-3 text-[14px] leading-[1.55] outline-none placeholder:text-faint ${inline ? "h-[140px]" : "min-h-0 flex-1"}`}
            />
            <div className="flex h-14 shrink-0 items-center gap-2.5 border-t border-line pr-3.5 pl-3">
                <MailButton kind="ghost" aria-label="Attach files">
                    <Paperclip className="size-3.5" />
                </MailButton>
                <span className="h-[18px] w-px bg-line-strong" />
                <Switch
                    on={composer.tracking}
                    onToggle={() => patch({ tracking: !composer.tracking })}
                    label={<span className={composer.tracking ? "text-fg" : "text-fg-2"}>Track opens and clicks</span>}
                />
                <KeyCap>⌘⇧T</KeyCap>
                {composer.tracking && (
                    <span className="truncate text-[12px] text-muted">
                        Adds a hidden image and tracked links. Never counts you here.
                    </span>
                )}
                <span className="flex-1" />
                {/* New mail has it in the header; a reply under a conversation has no header. */}
                {inline && <DiscardButton dispatch={dispatch} />}
                <MailButton kind="primary" onClick={() => dispatch({ type: "send" })}>
                    Send
                    <KeyCap>⌘↵</KeyCap>
                </MailButton>
            </div>
        </div>
    );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
    return (
        <div className="flex h-11 shrink-0 items-center gap-3 border-b border-line px-5">
            <span className="w-14 shrink-0 text-muted">{label}</span>
            {children}
        </div>
    );
}

/** No conversation open: the two keys that get you going. */
export function EmptyReader() {
    return (
        <div className="flex h-full flex-col items-center justify-center gap-2.5 text-muted">
            <span className="flex items-center gap-1.5">
                <KeyCap>J</KeyCap>
                <KeyCap>K</KeyCap>
                to move
            </span>
            <span className="flex items-center gap-1.5">
                <KeyCap>C</KeyCap>
                to write
            </span>
        </div>
    );
}

function DiscardButton({ dispatch }: { dispatch: Dispatch<Action> }) {
    return (
        <MailButton kind="ghost" onClick={() => dispatch({ type: "discard" })} className="gap-2">
            Discard <KeyCap>Esc</KeyCap>
        </MailButton>
    );
}
