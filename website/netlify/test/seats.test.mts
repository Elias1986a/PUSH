// node --test website/netlify/test/
import { test } from "node:test"
import assert from "node:assert/strict"
import { createHmac } from "node:crypto"
import { PRODUCTION, SANDBOX, reconcileSeats, resolveIds, countsAsSeat } from "../lib/seats.mts"
import { verifyWebhook } from "../lib/webhook.mts"

const env = { api: "https://api.polar.sh", token: "polar_oat_test" }
const ids = PRODUCTION

type Reply = { status: number; body: any }

// A fake Polar: the customer's orders and keys, and a log of what was changed.
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

const mainKey = (id: string, created: string, extra: any = {}) => ({
  id, key: `KEY-${id}`, status: "granted", benefit_id: ids.mainBenefit, limit_activations: 3, created_at: created, last_validated_at: null, ...extra,
})
const singleKey = (id: string, created: string, extra: any = {}) => ({
  id, key: `KEY-${id}`, status: "granted", benefit_id: ids.extraBenefit, limit_activations: 1, created_at: created, last_validated_at: null, ...extra,
})
const main = (status = "paid") => ({ id: crypto.randomUUID(), status, product_id: ids.mainProduct })
const single = (status = "paid") => ({ id: crypto.randomUUID(), status, product_id: ids.extraProduct })
const run = (o: Parameters<typeof fakePolar>[0], since?: number) => {
  const f = fakePolar(o)
  return reconcileSeats(env, ids, "cust", { call: f.call, since }).then((seats) => ({ seats, patches: f.patches }))
}

test("one $35 purchase: its own key, 3 Macs, nothing to change", async () => {
  const { seats, patches } = await run({ orders: [main()], keys: [mainKey("a", "2026-10-01T00:00:00Z")] })
  assert.equal(seats?.limit, 3)
  assert.equal(patches.length, 0)
})

// The giveaway: a free single stands on its own.
test("a single alone is a one-Mac key", async () => {
  const { seats, patches } = await run({ orders: [single()], keys: [singleKey("s", "2026-10-01T00:00:00Z")] })
  assert.equal(seats?.limit, 1)
  assert.equal(patches.length, 0)
})

// Single first, three later: the single's key is the main key for all four Macs.
test("single first, then the $35: the single's key takes all 4 places, the new key is switched off", async () => {
  const { seats, patches } = await run({
    orders: [single(), main()],
    keys: [singleKey("s", "2026-10-01T00:00:00Z"), mainKey("m", "2026-10-09T00:00:00Z")],
  })
  assert.equal(seats?.key.id, "s")
  assert.equal(seats?.limit, 4)
  assert.deepEqual(patches, [
    { path: "/v1/license-keys/s", body: { limit_activations: 4 } },
    { path: "/v1/license-keys/m", body: { status: "disabled" } },
  ])
})

test("the $35 first, then a single: the first key takes the fourth place", async () => {
  const { seats, patches } = await run({
    orders: [main(), single()],
    keys: [mainKey("m", "2026-10-01T00:00:00Z"), singleKey("s", "2026-10-09T00:00:00Z")],
  }, Date.parse("2026-10-09T00:00:00Z") - 300_000)
  assert.equal(seats?.key.id, "m")
  assert.equal(seats?.limit, 4)
  assert.equal(seats?.joinedExisting, true)
  assert.deepEqual(patches.map((p) => p.path), ["/v1/license-keys/m", "/v1/license-keys/s"])
})

test("a first purchase is not 'joining' anything", async () => {
  const { seats } = await run({ orders: [single()], keys: [singleKey("s", "2026-10-09T00:00:00Z")] }, Date.parse("2026-10-09T00:00:00Z") - 300_000)
  assert.equal(seats?.joinedExisting, false)
})

test("two singles on top of the $35 make five places", async () => {
  const { seats } = await run({
    orders: [main(), single(), single()],
    keys: [mainKey("m", "2026-10-01T00:00:00Z"), singleKey("s1", "2026-10-02T00:00:00Z"), singleKey("s2", "2026-10-03T00:00:00Z")],
  })
  assert.equal(seats?.limit, 5)
})

// Retried webhook, or the thank-you page and the webhook both running: no second change.
test("running it again changes nothing", async () => {
  const { seats, patches } = await run({
    orders: [main(), single()],
    keys: [mainKey("m", "2026-10-01T00:00:00Z", { limit_activations: 4 }), singleKey("s", "2026-10-09T00:00:00Z", { status: "disabled" })],
  })
  assert.equal(seats?.changed, false)
  assert.equal(patches.length, 0)
})

test("a later key already used on a Mac is left switched on", async () => {
  const { patches } = await run({
    orders: [main(), single()],
    keys: [mainKey("m", "2026-10-01T00:00:00Z"), singleKey("s", "2026-10-09T00:00:00Z", { last_validated_at: "2026-10-09T01:00:00Z" })],
  })
  assert.equal(patches.some((p) => p.path.endsWith("/s")), false)
})

test("a refund gives its places back; a partial refund keeps them", async () => {
  const refunded = await run({
    orders: [main(), single("refunded")],
    keys: [mainKey("m", "2026-10-01T00:00:00Z", { limit_activations: 4 }), singleKey("s", "2026-10-09T00:00:00Z", { status: "revoked" })],
  })
  assert.equal(refunded.seats?.limit, 3)
  const partial = await run({ orders: [single("partially_refunded")], keys: [singleKey("s", "2026-10-01T00:00:00Z")] })
  assert.equal(partial.seats?.limit, 1)
  assert.equal(countsAsSeat(single("void")), false)
  assert.equal(countsAsSeat(single("pending")), false)
})

// The first order refunded: its key is revoked, and the places move to the next key.
test("when the first key is refunded away, the next one becomes the main", async () => {
  const { seats, patches } = await run({
    orders: [single("refunded"), main()],
    keys: [singleKey("s", "2026-10-01T00:00:00Z", { status: "revoked" }), mainKey("m", "2026-10-09T00:00:00Z", { status: "disabled" })],
  })
  assert.equal(seats?.key.id, "m")
  assert.deepEqual(patches, [{ path: "/v1/license-keys/m", body: { status: "granted" } }])
})

test("nothing paid, or no key granted yet, means nothing to do", async () => {
  assert.equal((await run({ orders: [main("pending")], keys: [mainKey("a", "2026-10-01T00:00:00Z")] })).seats, null)
  assert.equal((await run({ orders: [main()], keys: [] })).seats, null)
})

test("keys from other benefits are not touched", async () => {
  const { seats, patches } = await run({
    orders: [main()],
    keys: [mainKey("a", "2026-10-01T00:00:00Z"), mainKey("other", "2026-10-02T00:00:00Z", { benefit_id: "unrelated" })],
  })
  assert.equal(seats?.key.id, "a")
  assert.equal(patches.length, 0)
})

test("a Polar failure throws, so a webhook is retried", async () => {
  const bad = fakePolar({ orders: [main(), single()], keys: [mainKey("m", "2026-10-01T00:00:00Z"), singleKey("s", "2026-10-09T00:00:00Z")], patchStatus: 500 })
  await assert.rejects(reconcileSeats(env, ids, "cust", { call: bad.call }), /licence key update 500/)
  const noSession = fakePolar({ orders: [], keys: [], sessionStatus: 401 })
  await assert.rejects(reconcileSeats(env, ids, "cust", { call: noSession.call }), /customer session 401/)
})

test("a session the page already holds is reused", async () => {
  const calls: string[] = []
  const f = fakePolar({ orders: [main()], keys: [mainKey("a", "2026-10-01T00:00:00Z")] })
  const spy = async (a: string, p: string, t: string, i?: RequestInit) => { calls.push(p); return f.call(a, p, t, i) }
  await reconcileSeats(env, ids, "cust", { customerToken: "polar_cst_held", call: spy })
  assert.equal(calls.some((c) => c.startsWith("/v1/customer-sessions/")), false)
})

// ---- benefit ids come from Polar's public store data ----

test("benefit ids are read from the store, so a recreated benefit is picked up", async () => {
  const store = { products: [
    { id: PRODUCTION.mainProduct, benefits: [{ id: "new-main", type: "license_keys" }, { id: "dl", type: "downloadables" }] },
    { id: PRODUCTION.extraProduct, benefits: [{ id: "new-extra", type: "license_keys" }, { id: "dl", type: "downloadables" }] },
  ] }
  const ids = await resolveIds("https://test-a.example", true, async () => ({ status: 200, body: store }))
  assert.equal(ids.mainBenefit, "new-main")
  assert.equal(ids.extraBenefit, "new-extra")
  assert.equal(ids.extraProduct, PRODUCTION.extraProduct)
})

test("an Extra Mac with no licence-key benefit yet, or Polar down, falls back to the built-in ids", async () => {
  const noKey = { products: [{ id: SANDBOX.extraProduct, benefits: [{ id: "dl", type: "downloadables" }] }] }
  const a = await resolveIds("https://test-b.example", false, async () => ({ status: 200, body: noKey }))
  assert.equal(a.extraBenefit, SANDBOX.extraBenefit)
  const b = await resolveIds("https://test-c.example", false, async () => { throw new Error("offline") })
  assert.deepEqual(b, SANDBOX)
  const c = await resolveIds("https://test-d.example", true, async () => ({ status: 503, body: {} }))
  assert.deepEqual(c, PRODUCTION)
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
