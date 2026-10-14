// Polar's API from a Netlify function: one call, JSON in and out.
export type PolarCall = (
  api: string,
  path: string,
  token: string,
  init?: RequestInit,
) => Promise<{ status: number; body: any }>

export const polar: PolarCall = async (api, path, token, init = {}) => {
  const res = await fetch(api + path, {
    ...init,
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), "content-type": "application/json", ...(init.headers ?? {}) },
  })
  const body = await res.json().catch(() => ({}))
  return { status: res.status, body }
}

export function polarEnv(): { api: string; token: string; production: boolean } | null {
  const token = Netlify.env.get("POLAR_ACCESS_TOKEN")
  if (!token) return null
  const production = Netlify.env.get("POLAR_SERVER") === "production"
  return { api: production ? "https://api.polar.sh" : "https://sandbox-api.polar.sh", token, production }
}
