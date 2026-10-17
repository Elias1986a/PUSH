// Higgsfield generations for the promo videos, through the API client in
// ~/Dev/higgsfield-mcp (direct API calls; the key comes from the Keychain).
//
//   node higgsfield-gen.mjs schema   <endpoint>
//   node higgsfield-gen.mjs estimate <endpoint> '<json input>'
//   node higgsfield-gen.mjs upload   <file>                 -> public URL
//   node higgsfield-gen.mjs generate <endpoint> '<json input>' <name>
//
// Every generate is priced first and refused if it would take the ledger
// (content/assets/videos/higgsfield/higgsfield-spend.json) past BUDGET_USD.
// Outputs land in content/assets/videos/higgsfield/<name>.<ext> (the git-ignored
// content library; describe each new clip in that folder's README).
import { readFile, writeFile, mkdir } from "node:fs/promises"
import { existsSync } from "node:fs"
import { join, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { homedir } from "node:os"

const client = await import(join(homedir(), "Dev/higgsfield-mcp/dist/higgsfield.js"))
const BUDGET_USD = Number(process.env.BUDGET_USD ?? 5)
const repo = join(dirname(fileURLToPath(import.meta.url)), "../..")
const outDir = join(repo, "content/assets/videos/higgsfield")
const ledgerPath = join(outDir, "higgsfield-spend.json")

async function ledger() {
  return existsSync(ledgerPath) ? JSON.parse(await readFile(ledgerPath, "utf8")) : { spentUsd: 0, items: [] }
}

const [cmd, a, b, c] = process.argv.slice(2)
await mkdir(outDir, { recursive: true })

if (cmd === "schema") {
  const catalog = JSON.parse(await readFile(join(homedir(), "Dev/higgsfield-mcp/catalog.json"), "utf8"))
  const e = catalog.entries.find((x) => x.endpoint === a)
  console.log(JSON.stringify({ notes: e?.notes, schema: e?.schema }, null, 1))
} else if (cmd === "estimate") {
  console.log(await client.estimate(a, JSON.parse(b)))
} else if (cmd === "upload") {
  console.log(await client.upload(a))
} else if (cmd === "generate") {
  const input = JSON.parse(b)
  const est = await client.estimate(a, input)
  const usd = Number(est.usd)
  const book = await ledger()
  if (!Number.isFinite(usd)) throw new Error(`No price for ${a}: ${JSON.stringify(est)}`)
  if (book.spentUsd + usd > BUDGET_USD) {
    console.log(`REFUSED: $${usd} would bring the total to $${(book.spentUsd + usd).toFixed(2)} (budget $${BUDGET_USD})`)
    process.exit(1)
  }
  console.log(`estimate $${usd}; spent so far $${book.spentUsd.toFixed(2)}`)
  const state = await client.submit(a, input)
  book.spentUsd += usd
  book.items.push({ name: c, endpoint: a, usd, requestId: state.requestId, at: new Date().toISOString(), prompt: input.prompt })
  await writeFile(ledgerPath, JSON.stringify(book, null, 1))
  const done = await client.waitFor(state.requestId, a, 15 * 60_000, (s, ms) =>
    process.stderr.write(`  ${s.status} ${Math.round(ms / 1000)}s\n`))
  if (done.status !== "completed") {
    console.log(`not completed: ${done.status} (request ${state.requestId})`)
    process.exit(1)
  }
  const files = []
  for (const [i, url] of done.outputs.entries()) {
    const ext = (url.split("?")[0].match(/\.(\w+)$/) || [, "bin"])[1]
    const path = join(outDir, `${c}${done.outputs.length > 1 ? `-${i + 1}` : ""}.${ext}`)
    const res = await fetch(url)
    await writeFile(path, Buffer.from(await res.arrayBuffer()))
    files.push(path)
  }
  console.log(JSON.stringify({ files, urls: done.outputs, totalSpentUsd: book.spentUsd.toFixed(2) }))
} else {
  console.log("usage: schema | estimate | upload | generate")
}
