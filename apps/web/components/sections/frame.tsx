import type { ReactNode } from "react";

/**
 * The page's blueprint: one 1200px column with hairline edges, sections stacked on hairlines and a small cross where
 * lines meet.
 */
export function Section({ id, children, className = "" }: { id?: string; children: ReactNode; className?: string }) {
    return (
        <section id={id} className={`relative mx-auto max-w-[1200px] border-t border-line ${className}`}>
            <Cross className="-top-[6px] -left-[6px]" />
            <Cross className="-top-[6px] -right-[6px]" />
            {children}
        </section>
    );
}

export function Cross({ className = "" }: { className?: string }) {
    return (
        <span aria-hidden className={`pointer-events-none absolute z-10 size-[11px] ${className}`}>
            <span className="absolute top-[5px] left-0 h-px w-full bg-fg-2/50" />
            <span className="absolute top-0 left-[5px] h-full w-px bg-fg-2/50" />
        </span>
    );
}

export function Heading({
    title,
    children,
    className = "",
}: {
    title: ReactNode;
    children?: ReactNode;
    className?: string;
}) {
    return (
        <div className={className}>
            <h2 className="text-[clamp(34px,4.6vw,56px)] leading-[1.02] font-semibold tracking-[-0.045em] text-balance">
                {title}
            </h2>
            {children && (
                <div className="mt-5 max-w-[470px] text-[17px] leading-[1.6] text-fg-2 [&_p+p]:mt-3">{children}</div>
            )}
        </div>
    );
}
