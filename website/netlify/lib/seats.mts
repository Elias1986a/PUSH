// One key, as many Macs as were bought.
//
// A customer's first key, whichever product it came from, is their main key.
// Everything else they buy adds places to it: 3 for each $35 PUSHTYPE, 1 for
// each $12 Extra Mac (a free single given away counts like any other). So a
// friend given a single can later buy the three, and ends up with one key on
// all of their Macs: iCloud Keychain hands it to each new Mac and nothing is
// pasted.
//
// The limit is always *set* from what the customer has paid for, never
// incremented: running it twice gives the same answer, a refund lowers it,
// and a retried webhook cannot add a place twice. The keys Polar issues for
// later orders are switched off while nobody has used them (nobody has seen
// them yet when this runs); a key already in use is left alone.
import { polar as defaultCall, type PolarCall } from "./polar.mts"

/** Places a $35 PUSHTYPE order gives, and an Extra Mac order. */
export const MAIN_MACS = 3
export const EXTRA_MACS = 1

export interface Ids {
  mainProduct: string
  extraProduct: string
  /** The licence-key benefit each product carries. */
  mainBenefit: string
  extraBenefit: string
}

export const SANDBOX: Ids = {
  mainProduct: "68857672-cc5b-45d4-8b10-abf40f523a11",
  extraProduct: "9deeaf9c-0f19-4e76-aad4-48826f58e2c2",
  mainBenefit: "d7043aa9-12d1-4f72-94f2-dcd1fc6610b9",
  extraBenefit: "54dc6cec-6c2d-4a1f-8979-f3bcfc1d5de6",
}

export const PRODUCTION: Ids = {
  mainProduct: "e05a47f1-acab-4221-af17-41dcb56a94e4",
  extraProduct: "b764aace-6737-4932-9028-75b890ac4c11",
  mainBenefit: "71c58e28-ee09-43b3-b4af-998f1d176d47",
  extraBenefit: "cea19ca1-e6c9-45d9-ae60-5c57f050c2c2",
}

export const idsFor = (production: boolean): Ids => (production ? PRODUCTION : SANDBOX)

const cache = new Map<string, { at: number; ids: Ids }>()

/**
 * The ids to use right now: the products are fixed, but each product's
 * licence-key benefit is read from Polar's public store data, so a benefit
 * that is deleted and made again (as happened to Extra Mac's) cannot leave
 * this pointing at a benefit that no longer exists. Falls back to the
 * built-in ids if Polar cannot be reached.
 */
export async function resolveIds(
  api: string,
  production: boolean,
  call: PolarCall = defaultCall,
  now: number = Date.now(),
): Promise<Ids> {
  const fallback = idsFor(production)
  const hit = cache.get(api)
  if (hit && now - hit.at < 5 * 60 * 1000) return hit.ids
  try {
    const store = await call(api, "/v1/customer-portal/organizations/pushtype", "")
    if (store.status !== 200) return fallback
    const licenceBenefit = (productId: string): string | undefined =>
      ((store.body.products ?? []) as any[])
        .find((p) => p.id === productId)
        ?.benefits?.find((b: any) => b.type === "license_keys")?.id
    const ids: Ids = {
      ...fallback,
      mainBenefit: licenceBenefit(fallback.mainProduct) ?? fallback.mainBenefit,
      extraBenefit: licenceBenefit(fallback.extraProduct) ?? fallback.extraBenefit,
    }
    cache.set(api, { at: now, ids })
    return ids
  } catch {
    return fallback
  }
}

export interface Seats {
  /** The customer's main key, as the customer portal shows it. */
  key: any
  /** How many Macs it now allows. */
  limit: number
  /** True when the main key is older than `since`: this purchase joined an existing licence. */
  joinedExisting: boolean
  changed: boolean
}

/** An order that still counts: paid, and not (fully) refunded. */
export const countsAsSeat = (order: any): boolean => order.status === "paid" || order.status === "partially_refunded"

/** Places one order is worth. */
export function seatsFor(order: any, ids: Ids): number {
  if (!countsAsSeat(order)) return 0
  if (order.product_id === ids.mainProduct) return MAIN_MACS
  if (order.product_id === ids.extraProduct) return EXTRA_MACS
  return 0
}

/**
 * Put all of the customer's paid places on their first key.
 * Returns null when there is nothing to do yet (no paid order, or no key has
 * been granted: the page waits, and a later event repeats this). Throws when
 * Polar fails, so a webhook is retried.
 */
export async function reconcileSeats(
  env: { api: string; token: string },
  ids: Ids,
  customerId: string,
  options: { customerToken?: string; since?: number; call?: PolarCall } = {},
): Promise<Seats | null> {
  const call = options.call ?? defaultCall
  let session = options.customerToken
  if (!session) {
    const made = await call(env.api, "/v1/customer-sessions/", env.token, {
      method: "POST",
      body: JSON.stringify({ customer_id: customerId }),
    })
    if (made.status !== 200 && made.status !== 201) throw new Error(`customer session ${made.status}`)
    session = made.body.token as string
  }

  const [orders, keys] = await Promise.all([
    call(env.api, "/v1/customer-portal/orders/?limit=100", session),
    call(env.api, "/v1/customer-portal/license-keys/?limit=100", session),
  ])
  if (orders.status !== 200) throw new Error(`orders ${orders.status}`)
  if (keys.status !== 200) throw new Error(`licence keys ${keys.status}`)

  const limit = ((orders.body.items ?? []) as any[]).reduce((sum, o) => sum + seatsFor(o, ids), 0)
  // Our keys that are not refunded away, oldest first; the oldest is the main one.
  const live = ((keys.body.items ?? []) as any[])
    .filter((k) => (k.benefit_id === ids.mainBenefit || k.benefit_id === ids.extraBenefit) && k.status !== "revoked")
    .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at))
  const base = live[0]
  if (!base || limit <= 0) return null

  const change: Record<string, unknown> = {}
  if (base.status === "disabled") change.status = "granted"
  if (base.limit_activations !== limit) change.limit_activations = limit
  let changed = false
  if (Object.keys(change).length > 0) {
    const updated = await call(env.api, `/v1/license-keys/${base.id}`, env.token, {
      method: "PATCH",
      body: JSON.stringify(change),
    })
    if (updated.status !== 200) throw new Error(`licence key update ${updated.status}`)
    changed = true
  }

  // The keys Polar issued for later orders: unused ones are switched off so
  // there is one live key. Anything already validated on a Mac stays.
  for (const k of live.slice(1)) {
    if (k.status !== "granted" || k.last_validated_at) continue
    const off = await call(env.api, `/v1/license-keys/${k.id}`, env.token, {
      method: "PATCH",
      body: JSON.stringify({ status: "disabled" }),
    })
    if (off.status !== 200) throw new Error(`licence key disable ${off.status}`)
    changed = true
  }

  const joinedExisting = options.since !== undefined && Date.parse(base.created_at) < options.since
  return { key: { ...base, status: "granted", limit_activations: limit }, limit, joinedExisting, changed }
}
