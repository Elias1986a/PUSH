# SEO at launch (10.0)

From the user's "PUSHTYPE SEO plan for launch (v10)" (2026-10-15).  The
`launch` branch already carries the site side; this file is what is left.

## Already on `launch`

- No `noindex` on the home, /benchmark/, /support/ or the four legal pages.
  Still `noindex`: 404, /thanks/ (license key), /support/sent/.
- Every indexed page has its own title, description and self-canonical
  (legal pages via `build_legal.py`; their canonical is the `.html` URL the
  site links to).
- Home title: `PUSHTYPE: Offline Dictation and Autocomplete for Mac`.
- JSON-LD on the home page: Organization + WebSite + SoftwareApplication
  ($35, version 10.0).  No rating until real reviews are on the page.
- `robots.txt`: everything allowed, AI training included; named group for the
  AI search crawlers; /thanks/ and /api/ disallowed in both groups.
- `sitemap.xml` with real lastmod dates: `python3 website/build_sitemap.py`.
- 192 px favicon on every page (Google wants 48 px or more).
- pushtype.netlify.app and main--pushtype.netlify.app 301 to pushtype.app.
- IndexNow: key file `website/3810bed91153a80be8dfacf84c5888ff.txt`;
  `netlify/functions/deploy-succeeded.mts` pings it after each production
  deploy with the pages whose lastmod is in the last two days.
- Already true before: www and http 301 to https://pushtype.app/, the 404 page
  returns 404, videos have posters and `preload="none"`, images have alt text.

## Just before merging `launch`

- [ ] `python3 website/build_sitemap.py` and commit, so lastmod is the launch date.
- [ ] If the price is no longer $35, change `price` in the home page JSON-LD.

## Launch day (about an hour, after the deploy)

1. [ ] Google Search Console: add a Domain property for pushtype.app (DNS
   verification in Netlify DNS), submit `https://pushtype.app/sitemap.xml`,
   URL-inspect the home page and /benchmark/ and Request indexing.
2. [ ] Search Console ▸ Settings ▸ Search generative AI: confirm Include.
3. [ ] Bing Webmaster Tools: import from Search Console, submit the sitemap.
   IndexNow needs no setup there: the key file is already on the site.
4. [ ] Check the hosts and crawlers:
   ```
   curl -sI -A "OAI-SearchBot/1.0" https://pushtype.app/ | head -1        # 200
   curl -sI -A "Claude-SearchBot/1.0" https://pushtype.app/ | head -1     # 200
   curl -sI -A "PerplexityBot/1.0" https://pushtype.app/ | head -1        # 200
   curl -sI https://www.pushtype.app/ | grep -i -E "^HTTP|^location"       # 301 → apex
   curl -sI https://pushtype.netlify.app/ | grep -i -E "^HTTP|^location"   # 301 → apex
   curl -s https://pushtype.app/3810bed91153a80be8dfacf84c5888ff.txt      # the key
   curl -s https://pushtype.app/robots.txt | head -3
   ```
5. [ ] Netlify ▸ Logs ▸ Functions ▸ deploy-succeeded shows `indexnow: N pages, status 200` (or 202).
6. [ ] Rich Results Test and PageSpeed Insights (mobile) on the home page.
7. [ ] Ask ChatGPT, Claude and Perplexity "What is pushtype.app and what does it
   cost?"  A wrong answer means the page is unclear on that fact.

## First 60 days

- Focused pages, each with its own title, H1, a short direct answer up top and a
  link home; add each to `PAGES` in `build_sitemap.py`: /talk/, /type/,
  /privacy/ (plain English, not the policy), /teleprompter/, /changelog/,
  and support articles as real questions arrive.  No mass-produced pages.
- /compare/ (vs Wispr Flow), built on the benchmark data: the user's call.
- Real mentions: Show HN, r/macapps, Product Hunt, AlternativeTo, MacUpdate,
  YouTube uploads of the demo videos with real titles, licenses to reviewers.
- Skip: llms.txt, rewriting for AI, "GEO" markup, FAQ markup, fake reviews.

## Monthly check

Search Console (Generative AI performance, Performance), Bing AI Performance,
Umami referrers (chatgpt.com, perplexity.ai, claude.ai, gemini.google.com), and
the same five prompts in ChatGPT, Claude, Perplexity and Google AI Mode: best
offline dictation app for Mac; private alternative to Wispr Flow; Mac
autocomplete that runs locally; dictation app with no subscription; Mac
teleprompter that follows your voice.
