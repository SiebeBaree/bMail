import type { NextConfig } from "next";

const config: NextConfig = {
    reactStrictMode: true,
    // The repo keeps one AGENTS.md at the root; next dev would add its own here.
    agentRules: false,
};

export default config;
