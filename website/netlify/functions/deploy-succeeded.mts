// Netlify runs this after every successful deploy (the file name is the
// event; Netlify signs the call, so it cannot be triggered from outside).
// On a production deploy it pings IndexNow with the pages that changed in the
// last two days, by their sitemap lastmod (lib/indexnow.mts).  Two days, not
// one: lastmod is the commit's local date and the deploy clock is UTC.
import { changedSince, pingBody, HOST } from "../lib/indexnow.mts"

export default async (req: Request) => {
  const { payload } = await req.json()
  if (payload?.context !== "production") return

  const sitemap = await fetch(`https://${HOST}/sitemap.xml`)
  if (!sitemap.ok) return console.log(`indexnow: sitemap ${sitemap.status}`)
  const since = new Date(Date.now() - 2 * 86_400_000).toISOString().slice(0, 10)
  const urls = changedSince(await sitemap.text(), since)
  if (urls.length === 0) return console.log("indexnow: no page changed")

  const reply = await fetch("https://api.indexnow.org/indexnow", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify(pingBody(urls)),
  })
  console.log(`indexnow: ${urls.length} pages, status ${reply.status}`)
}
