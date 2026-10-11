"use client";

import { motion } from "motion/react";
import type { ReactNode } from "react";

/**
 * Fades its content up the first time it scrolls into view, then never animates again. min-w-0 lets a grid column
 * shrink below the fixed-width replicas inside it, so Fit can zoom them down.
 */
export function Reveal({
    children,
    delay = 0,
    className = "",
}: {
    children: ReactNode;
    delay?: number;
    className?: string;
}) {
    return (
        <motion.div
            initial={{ opacity: 0, y: 28 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: "0px 0px -12% 0px" }}
            transition={{ duration: 0.9, delay, ease: [0.2, 0.7, 0.2, 1] }}
            className={`min-w-0 ${className}`}
        >
            {children}
        </motion.div>
    );
}
