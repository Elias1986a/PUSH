// The thank-you page's one-click setup: given the checkout Polar just sent
// the buyer back from, return that purchase's licence key and a link to
// download PUSHTYPE.
//
// Polar puts {CHECKOUT_ID} in the success URL (and sometimes a customer
// session token of its own, customer_session_token); only the buyer has
// them. The order number unlocks the key, so it works only for an hour after
// payment, and the page takes it out of the address bar at once. The Polar
// access token (scopes checkouts:read and customer_sessions:write) lives in
// the POLAR_ACCESS_TOKEN environment variable and never reaches the page.
// POLAR_SERVER is "sandbox" until the live store opens. Nothing is stored,
// and keys are never logged.
//
// Environment variables are frozen per deploy: after changing one, redeploy
// (Netlify ▸ Deploys ▸ Trigger deploy). A push that touches nothing under
// website/ is skipped by Netlify and does not count.
import type { Config } from "@netlify/functions"

const MAX_AGE_MS = 60 * 60 * 1000

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  })
}

async function polar(api: string, path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(api + path, {
    ...init,
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json", ...(init.headers ?? {}) },
  })
  const body = await res.json().catch(() => ({}))
  return { status: res.status, body: body as any }
}

export default async (req: Request) => {
  const params = new URL(req.url).searchParams
  const checkoutID = params.get("checkout_id") ?? ""
  const sessionToken = params.get("customer_session_token") ?? ""
  if (!/^[0-9a-f-]{36}$/i.test(checkoutID)) return json({ error: "bad_request" }, 400)

  const token = Netlify.env.get("POLAR_ACCESS_TOKEN")
  if (!token) return json({ error: "not_configured" }, 503)
  const api = Netlify.env.get("POLAR_SERVER") === "production" ? "https://api.polar.sh" : "https://sandbox-api.polar.sh"

  const checkout = await polar(api, `/v1/checkouts/${checkoutID}`, token)
  if (checkout.status === 404) return json({ error: "not_found" }, 404)
  if (checkout.status !== 200) {
    console.log(`checkout lookup failed: ${checkout.status}`)
    return json({ error: "polar_error", step: "checkout", status: checkout.status }, 502)
  }
  const co = checkout.body
  // Right after payment the checkout can still be "confirmed" for a moment.
  if (co.status !== "succeeded" || !co.customer_id) return json({ error: "not_ready", status: co.status }, 409)
  const createdAt = Date.parse(co.created_at)
  const paidAt = Date.parse(co.modified_at ?? co.created_at)
  if (!Number.isFinite(paidAt) || Date.now() - paidAt > MAX_AGE_MS) return json({ error: "expired" }, 410)

  // A short-lived session for this buyer only, to read what they own: the
  // one Polar handed the page if it did and it is theirs, else a new one.
  let customerToken = ""
  if (/^polar_cst_[A-Za-z0-9]+$/.test(sessionToken)) {
    const me = await polar(api, "/v1/customer-portal/customers/me", sessionToken)
    if (me.status === 200 && me.body.id === co.customer_id) customerToken = sessionToken
  }
  if (!customerToken) {
    const session = await polar(api, "/v1/customer-sessions/", token, {
      method: "POST",
      body: JSON.stringify({ customer_id: co.customer_id }),
    })
    if (session.status !== 201 && session.status !== 200) {
      console.log(`customer session failed: ${session.status}`)
      return json({ error: "polar_error", step: "session", status: session.status }, 502)
    }
    customerToken = session.body.token
  }

  const [keys, files] = await Promise.all([
    polar(api, "/v1/customer-portal/license-keys/?limit=100", customerToken),
    polar(api, "/v1/customer-portal/downloadables/?limit=100", customerToken),
  ])
  if (keys.status !== 200) {
    console.log(`licence keys failed: ${keys.status}`)
    return json({ error: "polar_error", step: "keys", status: keys.status, detail: keys.body?.detail }, 502)
  }

  // This purchase's key: granted, and made no earlier than the checkout. An
  // older key is another purchase's; until this one's exists, the page waits.
  const key = ((keys.body.items ?? []) as any[])
    .filter((k) => k.status === "granted" && Date.parse(k.created_at) >= createdAt - 5 * 60 * 1000)
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))[0]
  if (!key) return json({ error: "not_ready", status: "no_key_yet" }, 409)

  const downloads = files.status === 200 ? ((files.body.items ?? []) as any[]) : []
  const dmg = downloads.find((d) => String(d.file?.name ?? "").toLowerCase().endsWith(".dmg")) ?? downloads[0]

  return json({
    key: key.key,
    displayKey: key.display_key,
    macs: key.limit_activations,
    download: dmg?.file?.download?.url
      ? { url: dmg.file.download.url, name: dmg.file.name, size: dmg.file.size_readable }
      : null,
  })
}

export const config: Config = {
  path: "/api/purchase",
  method: "GET",
  rateLimit: { windowLimit: 30, windowSize: 60, aggregateBy: ["ip", "domain"] },
}
