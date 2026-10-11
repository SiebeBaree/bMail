import "react";

declare module "react" {
    interface CSSProperties {
        /** Reveal delay in milliseconds for [data-reveal] elements, read by globals.css. */
        "--d"?: number;
    }
}
