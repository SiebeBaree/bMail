"use client";

import { useEffect } from "react";

/** Opens bMail as soon as the page shows. Browsers ask first; the button stays for when that's dismissed. */
export function OpenOnLoad({ href }: { href: string }) {
    useEffect(() => {
        window.location.href = href;
    }, [href]);
    return null;
}
