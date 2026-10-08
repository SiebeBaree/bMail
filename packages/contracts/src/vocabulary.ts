// The domain's fixed vocabularies. The database enums are built from these same arrays, so a value can't exist on
// one side of the wire and not the other.

export const domainStatuses = ["pending", "verified", "failed"] as const;

/** Where a conversation lives. Sent is not a folder: it's every conversation with an outbound message. */
export const folders = ["inbox", "done", "spam", "trash"] as const;

export const directions = ["inbound", "outbound"] as const;

/** Lifecycle of an outbound message, driven by the send call and Resend's webhooks. */
export const deliveryStatuses = ["sending", "sent", "delivered", "delayed", "bounced", "complained", "failed"] as const;

export const eventTypes = [
    "sent",
    "delivered",
    "delayed",
    "bounced",
    "complained",
    "failed",
    "opened",
    "clicked",
] as const;

/**
 * Who caused an open or click. Only `person` counts: Apple's privacy proxy fetches images on delivery, Google's proxy
 * hides the reader and corporate scanners click every link seconds after delivery.
 */
export const eventSources = ["person", "apple_proxy", "google_proxy", "scanner"] as const;

export type DomainStatus = (typeof domainStatuses)[number];
export type Folder = (typeof folders)[number];
export type Direction = (typeof directions)[number];
export type DeliveryStatus = (typeof deliveryStatuses)[number];
export type EventType = (typeof eventTypes)[number];
export type EventSource = (typeof eventSources)[number];
