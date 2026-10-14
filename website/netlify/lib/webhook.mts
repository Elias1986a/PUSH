// Verifying a Polar webhook (the Standard Webhooks scheme): the request is
// signed with HMAC-SHA256 over "<webhook-id>.<webhook-timestamp>.<raw body>",
// and webhook-signature holds one or more "v1,<base64>" entries.
//
// Polar's secrets are "whsec_" + base64; older ones were used as plain text.
// Both readings are tried: only someone holding the secret can match either.
import { createHmac, timingSafeEqual } from "node:crypto"

export function verifyWebhook(
  secret: string,
  headers: { get(name: string): string | null },
  rawBody: string,
  nowMs: number = Date.now(),
  toleranceMs: number = 5 * 60 * 1000,
): boolean {
  const id = headers.get("webhook-id")
  const timestamp = headers.get("webhook-timestamp")
  const signature = headers.get("webhook-signature")
  if (!id || !timestamp || !signature || !secret) return false

  const seconds = Number(timestamp)
  if (!Number.isFinite(seconds) || Math.abs(nowMs - seconds * 1000) > toleranceMs) return false

  const keys: Buffer[] = secret.startsWith("whsec_")
    ? [Buffer.from(secret.slice(6), "base64"), Buffer.from(secret, "utf8")]
    : [Buffer.from(secret, "utf8"), Buffer.from(secret, "base64")]
  const given = signature
    .split(" ")
    .map((part) => part.split(","))
    .filter(([version, value]) => version === "v1" && value)
    .map(([, value]) => Buffer.from(value, "utf8"))
  const content = `${id}.${timestamp}.${rawBody}`

  for (const key of keys) {
    const expected = Buffer.from(createHmac("sha256", key).update(content).digest("base64"), "utf8")
    if (given.some((g) => g.length === expected.length && timingSafeEqual(g, expected))) return true
  }
  return false
}
