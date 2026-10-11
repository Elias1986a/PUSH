#!/usr/bin/env python3
"""Score small open language models as Type's autocomplete engine.

Each model runs under llama.cpp's `llama-server` and is asked to continue every
scenario in `autocomplete_scenarios.jsonl`. The prompt is the scenario's surface
line, a blank line, then the text before the caret — the caret text is the last
bytes of the prompt, so a base model simply continues it.

Greedy decoding is deterministic, so one 32-token run per scenario is cut to each
length preset (3/7/12/20 words) instead of re-running at four `n_predict`s: the
shorter run would be a prefix of the longer one.

The control (`qwen3-4b-instruct`) uses the pattern both earlier prototypes used:
an instruct model, chat template, "Continue the following text…".

Weights are read from CACHE when present (fast, pinned file), else fetched with
`-hf` on first use.

    python3 eval/run_autocomplete_eval.py [model-key ...]   # writes .autocomplete_eval.json
"""
import json, re, statistics, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

HERE = Path(__file__).parent
PORT = 8090
CACHE = Path.home() / "Library/Caches/PUSH-type-eval"

# key: (hf repo:quant, local file name)
MODELS = {
    "qwen3.5-0.8b-base": ("mradermacher/Qwen3.5-0.8B-Base-i1-GGUF:Q6_K", "Qwen3.5-0.8B-Base.i1-Q6_K.gguf"),
    "granite4-1b-base": ("ibm-granite/granite-4.0-1b-base-GGUF:Q4_K_M", "granite-4.0-1b-base-Q4_K_M.gguf"),
    "qwen3.5-2b-base": ("mradermacher/Qwen3.5-2B-Base-i1-GGUF:Q4_K_M", "Qwen3.5-2B-Base.i1-Q4_K_M.gguf"),
    "smollm3-3b-base": ("mradermacher/SmolLM3-3B-Base-i1-GGUF:Q4_K_M", "SmolLM3-3B-Base.i1-Q4_K_M.gguf"),
    "gemma4-e2b-base": ("mradermacher/gemma-4-E2B-i1-GGUF:Q4_K_M", "gemma-4-E2B.i1-Q4_K_M.gguf"),
    # Control: the instruct model both earlier prototypes used.
    "qwen3-4b-instruct": ("Qwen/Qwen3-4B-GGUF:Q4_K_M", "Qwen3-4B-Q4_K_M.gguf"),
}
INSTRUCT = {"qwen3-4b-instruct"}
# Granite 4.0 on Metal (Homebrew llama.cpp build 10566) turns to "@@@@" after a few
# requests; on the CPU it is fine. Its quality is scored on the CPU and its
# latency is not comparable with the others.
GPU_LAYERS = {"granite4-1b-base": "0"}
INSTRUCTION = ("Continue the following text from exactly where it stops. Reply with the "
               "continuation only, a few words, no quotes, no explanation.")

PRESETS = [3, 7, 12, 20]  # top word count of each length preset (1–3, 4–7, 8–12, 12–20)
N_PREDICT = 32            # enough tokens for 20 words
LEAK = re.compile(r"\b(Format|App|Title|Field|Domain|From):")

# ~1,500 characters of ordinary prose for the latency gate (a long email draft).
LONG_DRAFT = (
    "Hi team,\n\nThanks for a productive planning session yesterday. I wanted to put "
    "the main decisions in writing so we're all working from the same page before the "
    "holidays. First, the watchlist redesign moves into build next sprint. Design has "
    "signed off on the final mocks, and engineering estimated roughly three weeks for "
    "the iOS and Android clients, with the TV apps following a sprint later because of "
    "the remote-navigation work. Second, we agreed to run the new recommendations row "
    "as an A/B test in two markets before rolling it out everywhere. The success metric "
    "is watch time per active user over the first fourteen days, and we'll keep an eye "
    "on churn as a guardrail. Third, the content team asked for better tooling around "
    "artwork. Right now every season launch involves a lot of manual uploads and late "
    "fixes, and we lost almost a day on the last release because two posters had the "
    "wrong aspect ratio. Priya will write a short proposal for an automated check in the "
    "ingest pipeline and share it by Friday. Finally, a reminder that the quarterly "
    "review is on the twelfth. Each squad should bring a one-page summary of what "
    "shipped, what slipped and why, and what they need from the rest of us next quarter. "
    "Please keep it short; we only have an hour and a lot of ground to cover. If I've "
    "missed anything or got something wrong, reply here and I'll update the notes. "
    "Otherwise, I think we're in good shape, and I'm really looking forward to"
)


def prompt_for(s):
    return (s["surface"] + "\n\n" if s["surface"] else "") + s["before"]


def post(path, body):
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}{path}", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def heal(before):
    """Backs off the word the caret sits in, so the prompt ends on a token boundary.

    Returns (prompt text, forced start). A prompt ending mid-token ("appreci") makes
    the model see a word boundary that isn't there; instead the partial word is
    removed and a grammar forces the output to begin with it again (" appreci…"),
    which also covers a caret after a complete word ("take your").
    """
    m = re.search(r"([ \t]?)([^\W_][\w'’]*)$", before)  # same as TokenHealing.swift
    if not m:
        return before, ""
    return before[:m.start()], m.group(1) + m.group(2)


def gbnf_literal(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def complete(key, prompt, n_predict=N_PREDICT, cache=True, forced=""):
    """Returns (text, first-token ms, total ms). `forced` is stripped from the text."""
    if key in INSTRUCT:
        r = post("/v1/chat/completions", {
            "messages": [{"role": "system", "content": INSTRUCTION},
                         {"role": "user", "content": prompt}],
            "temperature": 0, "max_tokens": n_predict, "cache_prompt": cache,
            "chat_template_kwargs": {"enable_thinking": False}})
        text = r["choices"][0]["message"]["content"]
        t = r.get("timings", {})
    else:
        body = {"prompt": prompt, "n_predict": n_predict, "temperature": 0,
                "stop": ["\n"], "cache_prompt": cache}
        if forced:
            # Forced start, then anything: the "\n" stop cuts the line exactly as
            # unforced. Forbidding "\n" in the grammar made the model run on (and
            # a token like "\n@" then fell off the grammar's end).
            body["grammar"] = f"root ::= {gbnf_literal(forced)} ([^\\n] | \"\\n\")*"
        r = post("/completion", body)
        text, t = r["content"], r["timings"]
        if forced:
            text = text[len(forced):].rstrip("\n") if text.startswith(forced) else ""
    per_token = t.get("predicted_per_token_ms", 0)
    first = t.get("prompt_ms", 0) + per_token
    return text, first, t.get("prompt_ms", 0) + t.get("predicted_ms", 0)


def serve(key):
    repo, file = MODELS[key]
    src = ["-m", str(CACHE / file)] if (CACHE / file).exists() else ["-hf", repo]
    log = open(HERE / ".server.log", "w")
    proc = subprocess.Popen(["llama-server", *src, "--port", str(PORT), "-c", "4096", "-ngl", GPU_LAYERS.get(key, "99"),
                             "--no-webui"], stdout=log, stderr=subprocess.STDOUT)
    deadline = time.time() + 1800  # first -hf run downloads the weights
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"llama-server exited; see {HERE / '.server.log'}")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
                if json.load(r).get("status") == "ok":
                    return proc
        except Exception:
            pass
        time.sleep(1)
    proc.kill()
    raise RuntimeError("llama-server never became ready")


def norm(w):
    return re.sub(r"[^\w'-]", "", w.lower()) or w.lower()


def score(s, out):
    """Per-scenario quality against the expected continuation."""
    clean = out.split("\n")[0]
    exp = s["expected"].split()
    # Mid-word: the continuation must glue onto the partial word, not start a new one.
    if s.get("midword") and clean[:1].isspace():
        return {"first_word_hit": False, "prefix_words": 0}
    got = clean.split()
    n = 0
    for a, b in zip(got, exp):
        if norm(a) != norm(b):
            break
        n += 1
    return {"first_word_hit": n > 0, "prefix_words": n}


def repetitive(words):
    """A word three times running, or a repeated 3-gram: the usual small-model loop."""
    if any(words[i].lower() == words[i + 1].lower() == words[i + 2].lower() for i in range(len(words) - 2)):
        return True
    grams = [tuple(w.lower() for w in words[i:i + 3]) for i in range(len(words) - 2)]
    return len(grams) != len(set(grams))


def latency_gate(key):
    """First-token time for a 1,500-char prompt: cold (no cache) and per keystroke (cache hit)."""
    cold = []
    for i in range(10):
        # A different leading word each time defeats the prompt cache entirely.
        _, first, _ = complete(key, f"{i}. " + LONG_DRAFT, n_predict=8, cache=False)
        cold.append(first)
    warm, text = [], LONG_DRAFT
    complete(key, text, n_predict=8, cache=True)  # prime: the user has been typing this draft
    for ch in " seeing what we build":
        text += ch
        _, first, _ = complete(key, text, n_predict=8, cache=True)
        warm.append(first)
    return cold, warm


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))]


def evaluate(key, scenarios):
    proc = serve(key)
    try:
        complete(key, "Warm up the graph with")  # first call pays for setup
        result = {}
        for mode in ["raw"] if key in INSTRUCT else ["raw", "healed"]:
            rows = []
            for s in scenarios:
                before, forced = heal(s["before"]) if mode == "healed" else (s["before"], "")
                try:
                    out, first, total = complete(key, prompt_for({**s, "before": before}), forced=forced)
                except urllib.error.HTTPError:
                    # Granite 4.0: llama.cpp's grammar sampler throws on every request
                    # ("Unexpected empty grammar stack after accepting piece: @").
                    print(f"   {key}: {mode} failed on {s['id']}; mode skipped", file=sys.stderr)
                    rows = None
                    break
                rows.append({"id": s["id"], "surface": bool(s["surface"]), "midword": bool(s.get("midword")),
                             "out": out, "first_ms": first, "total_ms": total, **score(s, out)})
            if rows is not None:
                result[mode] = rows
        cold, warm = latency_gate(key)
        return {"modes": result, "cold_ms": cold, "warm_ms": warm}
    finally:
        proc.terminate()
        proc.wait()


def summary(key, res):
    print(f"\n== {key}")
    print(f"   1,500-char prompt first token: cold median {statistics.median(res['cold_ms']):.0f} / "
          f"p90 {pct(res['cold_ms'], 90):.0f} ms; per keystroke (cache hit) median "
          f"{statistics.median(res['warm_ms']):.0f} / p90 {pct(res['warm_ms'], 90):.0f} ms")
    for mode, rows in res["modes"].items():
        print(f"\n   -- {mode}")
        mode_summary(rows)
    if "healed" not in res["modes"] and key not in INSTRUCT:
        print("\n   -- healed: not supported (grammar sampler fails on this model)")


def mode_summary(rows):
    firsts = [r["first_ms"] for r in rows]
    print(f"   scenario first token: median {statistics.median(firsts):.0f} ms, p90 {pct(firsts, 90):.0f} ms")
    print("   | slice | n | first-word hit | mean prefix words |")
    print("   |---|---|---|---|")
    for name, sel in [("all", rows), ("with surface", [r for r in rows if r["surface"]]),
                      ("no surface", [r for r in rows if not r["surface"]]),
                      ("mid-word", [r for r in rows if r["midword"]])]:
        if sel:
            hit = sum(r["first_word_hit"] for r in sel)
            print(f"   | {name} | {len(sel)} | {hit}/{len(sel)} | "
                  f"{statistics.mean(r['prefix_words'] for r in sel):.2f} |")
    print("   | preset (≤ words) | leaks | repetitive | stopped short (< preset/2 words) |")
    print("   |---|---|---|---|")
    for top in PRESETS:
        cut = [r["out"].split("\n")[0].split()[:top] for r in rows]
        leaks = sum(bool(LEAK.search(" ".join(c))) for c in cut)
        reps = sum(repetitive(c) for c in cut)
        short = sum(len(c) < top / 2 for c in cut)
        print(f"   | {top} | {leaks} | {reps} | {short} |")


def main():
    scenarios = [json.loads(l) for l in (HERE / "autocomplete_scenarios.jsonl").read_text().splitlines() if l]
    out = HERE / ".autocomplete_eval.json"
    report = json.loads(out.read_text()) if out.exists() else {}
    for key in sys.argv[1:] or list(MODELS):
        report[key] = evaluate(key, scenarios)
        out.write_text(json.dumps(report, indent=1, ensure_ascii=False))
    for key, res in report.items():
        summary(key, res)


if __name__ == "__main__":
    main()
