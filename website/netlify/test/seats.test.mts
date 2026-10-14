// node --test website/netlify/test/
import { test } from "node:test"
import assert from "node:assert/strict"
import { createHmac } from "node:crypto"
import { BASE_MACS, PRODUCTION, reconcileSeats, countsAsSeat } from "../lib/seats.mts"
import { verifyWebhook } from "../lib/webhook.mts"

const env = { api: "https://api.polar.sh", token: "polar_oat_test" }
const ids = PRODUCTION

type Reply = { status: number; body: any }

// A fake Polar: the customer's extra-Mac orders and main keys, and a log of what was changed.
function fakePolar(opts: { orders: any[]; keys: any[]; sessionStatus?: number; patchStatus?: number }) {
  const patches: { path: string; body: any }[] = []
  const call = async (_api: string, path: string, _token: string, init?: RequestInit): Promise<Reply> => {
    if (path.startsWith("/v1/customer-sessions/")) {
      return opts.sessionStatus && opts.sessionStatus >= 400
        ? { status: opts.sessionStatus, body: {} }
        : { status: 201, body: { token: "polar_cst_x" } }
    }
    if (path.startsWith("/v1/customer-portal/orders/")) return { status: 200, body: { items: opts.orders } }
    if (path.startsWith("/v1/customer-portal/license-keys/")) return { status: 200, body: { items: opts.keys } }
    if (path.startsWith("/v1/license-keys/") && init?.method === "PATCH") {
      patches.push({ path, body: JSON.parse(String(init.body)) })
      return { status: opts.patchStatus ?? 200, body: {} }
    }
    throw new Error(`unexpected call ${path}`)
  }
  return { call, patches }
}

const key = (id: string, created: string, limit = 3, extra: any = {}) => ({
  id, key: `KEY-${id}`, display_key: `****-${id}`, status: "granted",
  benefit_id: ids.mainBenefit, limit_activations: limit, created_at: created, ...extra,
})
const order = (status: string) => ({ id: crypto.randomUUID(), status, product_id: ids.extraProduct })

test("one paid Extra Mac raises the main key from 3 to 4", async () => {
  const { call, patches } = fakePolar({ orders: [order("paid")], keys: [key("a", "2026-10-01T00:00:00Z")] })
  const seats = await reconcileSeats(env, ids, "cust", undefined, call)
  assert.equal(seats?.limit, BASE_MACS + 1)
  assert.equal(seats?.changed, true)
  assert.deepEqual(patches, [{ path: "/v1/license-keys/a", body: { limit_activations: 4 } }])
})

test("two Extra Macs make five places", async () => {
  const { call, patches } = fakePolar({ orders: [order("paid"), order("paid")], keys: [key("a", "2026-10-01T00:00:00Z")] })
  assert.equal((await reconcileSeats(env, ids, "cust", undefined, call))?.limit, 5)
  assert.equal(patches[0].body.limit_activations, 5)
})

// Retried webhook, or the thank-you page and the webhook both running: no second change.
test("running it again changes nothing", async () => {
  const { call, patches } = fakePolar({ orders: [order("paid")], keys: [key("a", "2026-10-01T00:00:00Z", 4)] })
  const seats = await reconcileSeats(env, ids, "cust", undefined, call)
  assert.equal(seats?.changed, false)
  assert.equal(patches.length, 0)
})

test("a refunded Extra Mac gives its place back; a partial refund keeps it", async () => {
  const refunded = fakePolar({ orders: [order("paid"), order("refunded")], keys: [key("a", "2026-10-01T00:00:00Z", 5)] })
  assert.equal((await reconcileSeats(env, ids, "cust", undefined, refunded.call))?.limit, 4)
  const partial = fakePolar({ orders: [order("partially_refunded")], keys: [key("a", "2026-10-01T00:00:00Z", 3)] })
  assert.equal((await reconcileSeats(env, ids, "cust", undefined, partial.call))?.limit, 4)
  assert.equal(countsAsSeat(order("void")), false)
  assert.equal(countsAsSeat(order("pending")), false)
})

test("with two main keys the oldest takes the places", async () => {
  const { call, patches } = fakePolar({
    orders: [order("paid")],
    keys: [key("new", "2026-10-10T00:00:00Z"), key("old", "2026-09-01T00:00:00Z")],
  })
  await reconcileSeats(env, ids, "cust", undefined, call)
  assert.equal(patches[0].path, "/v1/license-keys/old")
})

test("revoked keys and other benefits' keys are not touched", async () => {
  const { call, patches } = fakePolar({
    orders: [order("paid")],
    keys: [key("dead", "2026-09-01T00:00:00Z", 3, { status: "revoked" }), key("other", "2026-09-02T00:00:00Z", 1, { benefit_id: "extra-benefit" })],
  })
  assert.equal(await reconcileSeats(env, ids, "cust", undefined, call), null)
  assert.equal(patches.length, 0)
})

test("an Extra Mac with no main licence has nothing to add to", async () => {
  const { call } = fakePolar({ orders: [order("paid")], keys: [] })
  assert.equal(await reconcileSeats(env, ids, "cust", undefined, call), null)
})

test("a Polar failure throws, so a webhook is retried", async () => {
  const bad = fakePolar({ orders: [order("paid")], keys: [key("a", "2026-10-01T00:00:00Z")], patchStatus: 500 })
  await assert.rejects(reconcileSeats(env, ids, "cust", undefined, bad.call), /licence key update 500/)
  const noSession = fakePolar({ orders: [], keys: [], sessionStatus: 401 })
  await assert.rejects(reconcileSeats(env, ids, "cust", undefined, noSession.call), /customer session 401/)
})

test("a session the page already holds is reused", async () => {
  const calls: string[] = []
  const { call } = fakePolar({ orders: [], keys: [key("a", "2026-10-01T00:00:00Z")] })
  const spy = async (a: string, p: string, t: string, i?: RequestInit) => { calls.push(p); return call(a, p, t, i) }
  await reconcileSeats(env, ids, "cust", "polar_cst_held", spy)
  assert.equal(calls.some((c) => c.startsWith("/v1/customer-sessions/")), false)
})

// ---- webhook signatures (Standard Webhooks) ----

const sign = (secretKey: Buffer, id: string, ts: string, body: string) =>
  "v1," + createHmac("sha256", secretKey).update(`${id}.${ts}.${body}`).digest("base64")
const headers = (h: Record<string, string>) => ({ get: (n: string) => h[n] ?? null })
const now = 1_800_000_000_000
const ts = String(now / 1000)
const body = '{"type":"order.paid"}'

test("a whsec_ secret signed the Standard Webhooks way verifies", () => {
  const raw = Buffer.from("super-secret-bytes-123")
  const secret = "whsec_" + raw.toString("base64")
  const h = headers({ "webhook-id": "msg_1", "webhook-timestamp": ts, "webhook-signature": sign(raw, "msg_1", ts, body) })
  assert.equal(verifyWebhook(secret, h, body, now), true)
})

test("a plain-text secret (Polar's older scheme) verifies", () => {
  const secret = "my-plain-secret"
  const h = headers({ "webhook-id": "m", "webhook-timestamp": ts, "webhook-signature": sign(Buffer.from(secret), "m", ts, body) })
  assert.equal(verifyWebhook(secret, h, body, now), true)
})

test("a changed body, the wrong secret, or a missing header is refused", () => {
  const raw = Buffer.from("k")
  const secret = "whsec_" + raw.toString("base64")
  const good = { "webhook-id": "m", "webhook-timestamp": ts, "webhook-signature": sign(raw, "m", ts, body) }
  assert.equal(verifyWebhook(secret, headers(good), body + " ", now), false)
  assert.equal(verifyWebhook("whsec_" + Buffer.from("other").toString("base64"), headers(good), body, now), false)
  assert.equal(verifyWebhook(secret, headers({ ...good, "webhook-signature": "" }), body, now), false)
  assert.equal(verifyWebhook("", headers(good), body, now), false)
})

test("an old timestamp is refused, and any one of several signatures may match", () => {
  const raw = Buffer.from("k")
  const secret = "whsec_" + raw.toString("base64")
  const oldTs = String(now / 1000 - 3600)
  const stale = { "webhook-id": "m", "webhook-timestamp": oldTs, "webhook-signature": sign(raw, "m", oldTs, body) }
  assert.equal(verifyWebhook(secret, headers(stale), body, now), false)
  const two = { "webhook-id": "m", "webhook-timestamp": ts, "webhook-signature": "v1,AAAA " + sign(raw, "m", ts, body) }
  assert.equal(verifyWebhook(secret, headers(two), body, now), true)
})
