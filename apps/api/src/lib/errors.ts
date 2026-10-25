// Errors a service may throw on purpose. The error handler in app.ts maps each to its status code and passes the
// message through, so every message here is written for the person reading it in the app.

/** 400 for input that passed validation but that something downstream turned down, like a Resend key Resend refuses. */
export class BadRequestError extends Error {
    readonly name = "BadRequestError";
}

export class NotFoundError extends Error {
    readonly name = "NotFoundError";
}

export class ConflictError extends Error {
    readonly name = "ConflictError";
}

/** Resend, storage or DNS said no. 502, because the request was fine and the dependency wasn't. */
export class UpstreamError extends Error {
    readonly name = "UpstreamError";
}
