import type { ComponentProps, ReactNode } from "react";

/** Building blocks of the app replicas, after MailKit/DesignSystem/Controls.swift. */

export function KeyCap({ children, className = "" }: { children: ReactNode; className?: string }) {
    return (
        <kbd
            className={`inline-flex h-[18px] min-w-[18px] items-center justify-center rounded-[4px] border border-line-strong bg-raised px-1 font-mono text-[11px] leading-none text-fg-2 ${className}`}
        >
            {children}
        </kbd>
    );
}

export function Keys({ keys }: { keys: readonly string[] }) {
    return (
        <span className="flex gap-1">
            {keys.map((key) => (
                <KeyCap key={key}>{key}</KeyCap>
            ))}
        </span>
    );
}

const initials = (name: string) =>
    name
        .split(/[\s.@]+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((word) => word[0])
        .join("")
        .toUpperCase();

/** Initials in a circle. No photos: a list of faces is noise. */
export function Avatar({ name, size = 28 }: { name: string; size?: number }) {
    return (
        <span
            aria-hidden
            className="inline-flex shrink-0 items-center justify-center rounded-full bg-selected font-medium text-fg-2"
            style={{ width: size, height: size, fontSize: size * 0.38 }}
        >
            {initials(name)}
        </span>
    );
}

const dotColors = {
    success: "bg-success",
    warning: "bg-warning",
    danger: "bg-danger",
    muted: "bg-muted",
} as const;

export function StatusDot({ tone }: { tone: keyof typeof dotColors }) {
    return <span className={`inline-block size-[7px] shrink-0 rounded-full ${dotColors[tone]}`} />;
}

const buttonKinds = {
    primary: "bg-fg px-3 text-canvas hover:bg-fg/90",
    secondary: "border border-line-strong px-3 text-fg hover:bg-hover",
    ghost: "px-2 text-fg-2 hover:bg-hover hover:text-fg",
} as const;

export function MailButton({
    kind,
    className = "",
    ...props
}: ComponentProps<"button"> & { kind: keyof typeof buttonKinds }) {
    return (
        <button
            type="button"
            className={`inline-flex h-[30px] shrink-0 items-center gap-2 rounded-md text-[13px] font-medium whitespace-nowrap ${buttonKinds[kind]} ${className}`}
            {...props}
        />
    );
}

/** A small switch, blue when on. */
export function Switch({ on, onToggle, label }: { on: boolean; onToggle: () => void; label: ReactNode }) {
    return (
        <button type="button" role="switch" aria-checked={on} onClick={onToggle} className="flex items-center gap-2">
            <span
                className={`flex h-4 w-7 items-center rounded-full p-0.5 transition-colors ${on ? "justify-end bg-accent" : "justify-start bg-line-strong"}`}
            >
                <span className={`size-3 rounded-full ${on ? "bg-white" : "bg-muted"}`} />
            </span>
            {label}
        </button>
    );
}

/** A macOS window: rounded, hairline edge, traffic lights in the toolbar row. */
export function Window({
    children,
    className = "",
    lights = true,
}: {
    children: ReactNode;
    className?: string;
    lights?: boolean;
}) {
    return (
        <div
            className={`relative overflow-hidden rounded-[16px] bg-canvas text-[13px] text-fg shadow-[0_0_0_1px_rgb(255_255_255/0.1),0_40px_120px_-20px_rgb(0_0_0/0.9),0_0_0_0.5px_rgb(0_0_0)] ${className}`}
        >
            {lights && <TrafficLights className="absolute top-[19px] left-[18px] z-10" />}
            {children}
        </div>
    );
}

export function TrafficLights({ className = "" }: { className?: string }) {
    return (
        <span aria-hidden className={`flex gap-2 ${className}`}>
            <span className="size-3 rounded-full bg-[#ff5f57]" />
            <span className="size-3 rounded-full bg-[#febc2e]" />
            <span className="size-3 rounded-full bg-[#28c840]" />
        </span>
    );
}
