// node --test website/netlify/test/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { changedSince, pingBody, KEY } from "../lib/indexnow.mts"

const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://pushtype.app/</loc><lastmod>2026-11-02</lastmod></url>
  <url><loc>https://pushtype.app/benchmark/</loc><lastmod>2026-10-11</lastmod></url>
  <url><loc>https://pushtype.app/support/</loc></url>
</urlset>`

test("pings only pages changed on or after the date", () => {
  assert.deepEqual(changedSince(sitemap, "2026-11-01"), ["https://pushtype.app/"])
  assert.deepEqual(changedSince(sitemap, "2026-10-11"), ["https://pushtype.app/", "https://pushtype.app/benchmark/"])
  assert.deepEqual(changedSince(sitemap, "2026-12-01"), [])
})

test("the key file on the site holds the key", () => {
  const file = new URL(`../../${KEY}.txt`, import.meta.url)
  assert.equal(readFileSync(file, "utf8").trim(), KEY)
  assert.equal(pingBody(["https://pushtype.app/"]).keyLocation, `https://pushtype.app/${KEY}.txt`)
})

test("the real sitemap parses", () => {
  const real = readFileSync(new URL("../../sitemap.xml", import.meta.url), "utf8")
  assert.ok(changedSince(real, "2000-01-01").length >= 7)
})
