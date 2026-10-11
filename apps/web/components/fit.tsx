"use client";

import { type ReactNode, useLayoutEffect, useRef, useState } from "react";

/**
 * Shows fixed-size content at its real pixel size and shrinks it with CSS zoom when the column is narrower. Zoom
 * relays out instead of scaling a bitmap, so text stays sharp.
 *
 * The content renders only once measured. That keeps the replicas' fake mail out of the server HTML that crawlers and
 * AI assistants read, and data-nosnippet keeps it out of Google's snippets after rendering. Pass `height` when the
 * content has a fixed size and the space is reserved up front, so nothing below shifts when it appears.
 */
export function Fit({
    width,
    height,
    children,
    className = "",
}: {
    width: number;
    height?: number;
    children: ReactNode;
    className?: string;
}) {
    const ref = useRef<HTMLDivElement>(null);
    const [zoom, setZoom] = useState<number | null>(null);

    useLayoutEffect(() => {
        const element = ref.current;
        if (!element) return;
        const observer = new ResizeObserver(([entry]) => {
            setZoom(Math.min(1, (entry?.contentRect.width ?? width) / width));
        });
        observer.observe(element);
        return () => observer.disconnect();
    }, [width]);

    return (
        <div
            ref={ref}
            data-nosnippet
            className={`mx-auto flex w-full justify-center ${className}`}
            style={height ? { aspectRatio: `${width} / ${height}`, maxWidth: width } : undefined}
        >
            {zoom !== null && <div style={{ width, zoom }}>{children}</div>}
        </div>
    );
}
