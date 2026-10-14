// One licence, as many Macs as were bought.
//
// The $35 PUSHTYPE licence key allows 3 Macs. Each "Extra Mac" ($12) is not a
// key of its own: it adds one place to the buyer's main key, so every Mac
// shares that key, iCloud Keychain hands it to a new Mac, and nothing has to
// be pasted. The limit is always *set*, never incremented: 3 + the number of
// paid Extra Mac orders the customer has. Running it twice gives the same
// answer, a refund lowers it, and a retried webhook cannot add a place twice.
import { polar as defaultCall, type PolarCall } from "./polar.mts"

export const BASE_MACS = 3

export interface Ids {
  /** The $35 product, and the licence-key benefit it carries. */
  mainProduct: string
  mainBenefit: string
  /** The $12 add-on. */
  extraProduct: string
}

export const SANDBOX: Ids = {
  mainProduct: "68857672-cc5b-45d4-8b10-abf40f523a11",
  mainBenefit: "d7043aa9-12d1-4f72-94f2-dcd1fc6610b9",
  extraProduct: "9deeaf9c-0f19-4e76-aad4-48826f58e2c2",
}

export const PRODUCTION: Ids = {
  mainProduct: "e05a47f1-acab-4221-af17-41dcb56a94e4",
  mainBenefit: "71c58e28-ee09-43b3-b4af-998f1d176d47",
  extraProduct: "b764aace-6737-4932-9028-75b890ac4c11",
}

export const idsFor = (production: boolean): Ids => (production ? PRODUCTION : SANDBOX)

export interface Seats {
  /** The customer's main licence key, as the customer portal shows it. */
  key: any
  /** How many Macs it now allows. */
  limit: number
  /** How many Extra Macs are counted. */
  extras: number
  changed: boolean
}

/** An order that still counts: paid, and not (fully) refunded. */
export const countsAsSeat = (order: any): boolean => order.status === "paid" || order.status === "partially_refunded"

/**
 * Set the customer's main key to BASE_MACS + their paid Extra Macs.
 * Returns null when they have no main key (an Extra Mac alone has nothing to
 * add to). Throws when Polar fails, so a webhook can be retried.
 */
export async function reconcileSeats(
  env: { api: string; token: string },
  ids: Ids,
  customerId: string,
  customerToken?: string,
  call: PolarCall = defaultCall,
): Promise<Seats | null> {
  let session = customerToken
  if (!session) {
    const made = await call(env.api, "/v1/customer-sessions/", env.token, {
      method: "POST",
      body: JSON.stringify({ customer_id: customerId }),
    })
    if (made.status !== 200 && made.status !== 201) throw new Error(`customer session ${made.status}`)
    session = made.body.token as string
  }

  const [orders, keys] = await Promise.all([
    call(env.api, `/v1/customer-portal/orders/?product_id=${ids.extraProduct}&limit=100`, session),
    call(env.api, `/v1/customer-portal/license-keys/?benefit_id=${ids.mainBenefit}&limit=100`, session),
  ])
  if (orders.status !== 200) throw new Error(`orders ${orders.status}`)
  if (keys.status !== 200) throw new Error(`licence keys ${keys.status}`)

  const extras = ((orders.body.items ?? []) as any[]).filter(countsAsSeat).length
  // More than one main key (two licences bought): the oldest one takes the places.
  const main = ((keys.body.items ?? []) as any[])
    .filter((k) => k.status === "granted" && k.benefit_id === ids.mainBenefit)
    .sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at))[0]
  if (!main) return null

  const limit = BASE_MACS + extras
  if (main.limit_activations === limit) return { key: main, limit, extras, changed: false }

  const updated = await call(env.api, `/v1/license-keys/${main.id}`, env.token, {
    method: "PATCH",
    body: JSON.stringify({ limit_activations: limit }),
  })
  if (updated.status !== 200) throw new Error(`licence key update ${updated.status}`)
  return { key: { ...main, limit_activations: limit }, limit, extras, changed: true }
}
