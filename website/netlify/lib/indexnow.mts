// IndexNow tells Bing (which feeds Copilot and ChatGPT Search), Yandex and
// others that a page changed, so they recrawl in minutes instead of days.
// The key is public by design: search engines check that the file
// /<key>.txt on the site holds it, which proves the site sent the ping.
export const HOST = "pushtype.app"
export const KEY = "3810bed91153a80be8dfacf84c5888ff"

// The pages whose sitemap lastmod is on or after `since` (YYYY-MM-DD).
// build_sitemap.py keeps lastmod at the date each page last changed, so a
// deploy that only touched the app pings nothing.
export function changedSince(sitemap: string, since: string): string[] {
  const urls: string[] = []
  for (const entry of sitemap.matchAll(/<url>([\s\S]*?)<\/url>/g)) {
    const loc = entry[1].match(/<loc>([^<]+)<\/loc>/)?.[1]
    const lastmod = entry[1].match(/<lastmod>([^<]+)<\/lastmod>/)?.[1]
    if (loc && lastmod && lastmod.slice(0, 10) >= since) urls.push(loc)
  }
  return urls
}

export function pingBody(urlList: string[]) {
  return { host: HOST, key: KEY, keyLocation: `https://${HOST}/${KEY}.txt`, urlList }
}
