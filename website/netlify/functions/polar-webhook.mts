// Polar calls this after an order is paid, refunded or changed, and when a
// licence key is granted. It puts everything the customer has paid for on
// their first key (lib/seats.mts), so all their Macs share one key.
//
// Setup in Polar (Settings ▸ Webhooks ▸ Add endpoint): URL
// https://pushtype.app/api/polar-webhook, format Raw, events order.paid,
// order.refunded, order.updated, benefit_grant.created and
// benefit_grant.updated, and a generated secret, which goes in
// the Netlify variable POLAR_WEBHOOK_SECRET (marked secret). The access token
// also needs the license_keys:write scope. Nothing is stored and keys are
// never logged.
import type { Config } from "@netlify/functions"
import { reconcileSeats, resolveIds } from "../lib/seats.mts"
import { polarEnv } from "../lib/polar.mts"
import { verifyWebhook } from "../lib/webhook.mts"

const ORDER_EVENTS = new Set(["order.paid", "order.refunded", "order.updated"])
// The key is granted a moment after the order is paid; this is the event
// that arrives when it exists.
const GRANT_EVENTS = new Set(["benefit_grant.created", "benefit_grant.updated"])

export default async (req: Request) => {
  const secret = Netlify.env.get("POLAR_WEBHOOK_SECRET")
  const env = polarEnv()
  if (!secret || !env) return new Response("not configured", { status: 503 })

  const raw = await req.text()
  if (!verifyWebhook(secret, req.headers, raw)) return new Response("bad signature", { status: 403 })

  let event: any
  try { event = JSON.parse(raw) } catch { return new Response("bad json", { status: 400 }) }
  const ids = await resolveIds(env.api, env.production)
  const data = event?.data
  const isOrder = ORDER_EVENTS.has(event?.type)
  const isGrant = GRANT_EVENTS.has(event?.type)
  // Anything else is acknowledged, so Polar does not retry it.
  if (!isOrder && !isGrant) return new Response("ignored", { status: 202 })
  const customerId = data?.customer_id ?? data?.customer?.id
  const ours = isOrder
    ? [ids.mainProduct, ids.extraProduct].includes(data?.product_id ?? data?.product?.id)
    : [ids.mainBenefit, ids.extraBenefit].includes(data?.benefit_id ?? data?.benefit?.id)
  if (!ours || !customerId) return new Response("ignored", { status: 202 })

  try {
    const seats = await reconcileSeats(env, ids, customerId)
    // Counts only: never the key.
    console.log(seats ? `seats: limit ${seats.limit}, changed ${seats.changed}` : "seats: nothing to do yet")
    return new Response("ok", { status: 202 })
  } catch (error) {
    // A Polar error is worth a retry; Polar tries again with backoff.
    console.log(`seats failed: ${(error as Error).message}`)
    return new Response("try again", { status: 500 })
  }
}

export const config: Config = { path: "/api/polar-webhook", method: "POST" }
