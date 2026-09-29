#!/usr/bin/env python3
"""Score small open language models as PUSH's self-correction resolver.

Each model runs under llama.cpp's `llama-server` (downloaded from Hugging Face on
first use) and is asked about every sentence in `self_corrections.jsonl` that holds
a correction marker; sentences without one pass through untouched, as in the app.

The model may only *remove* words. Its answer is accepted when every word in it is
a word the speaker said (a sub-multiset of the input's words), which is what keeps
it from putting words in the user's mouth. A rejected or failed answer falls back
to the rules' output (`.rules_output.json`, written by SelfCorrectionEvalTests with
PUSH_EVAL_RULES_OUT set) — the same fallback the app would use.

    PUSH_EVAL_RULES_OUT=$PWD/eval/.rules_output.json swift test --filter SelfCorrectionEval
    python3 eval/run_llm_eval.py [model-key ...]
"""
import json, re, statistics, subprocess, sys, time, urllib.request
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).parent
PORT = 8089

MODELS = {
    "qwen2.5-0.5b": "Qwen/Qwen2.5-0.5B-Instruct-GGUF:q4_k_m",
    "qwen2.5-1.5b": "Qwen/Qwen2.5-1.5B-Instruct-GGUF:q4_k_m",
    "llama3.2-1b": "bartowski/Llama-3.2-1B-Instruct-GGUF:Q4_K_M",
}

# Same lists as TextProcessing+SelfCorrections.swift.
MARKERS = ["i mean", "i meant", "no wait", "wait no", "make that", "or rather", "sorry",
           "correction", "scratch that", "let me start over", "start over", "delete that"]

SYSTEM = """You fix dictated text where the speaker corrected themselves.

If the speaker corrected a mistake (with words like "I mean", "sorry", "no wait", "make that", "correction", "scratch that", "start over"), rewrite the text so it says only what they meant: remove the mistaken words, the correction phrase, and any punctuation left dangling. Keep every other word exactly as spoken.

If those words are ordinary speech and nothing is being corrected (an apology, emphasis, "I mean it", "what I mean is", a hedge), return the text exactly as given.

Never add words the speaker did not say. Reply with the text only."""

# Teaching examples. None of these appear in the eval set.
SHOTS = [
    ("Order ten boxes, I mean twelve boxes.", "Order twelve boxes."),
    ("Put the meeting in the small room on the third floor, sorry, the big conference room.",
     "Put the meeting in the big conference room."),
    ("The flight lands in Chicago. I mean Denver.", "The flight lands in Denver."),
    ("Pick up milk, scratch that, pick up bread.", "Pick up bread."),
    ("I'm so sorry about the mix-up.", "I'm so sorry about the mix-up."),
    ("I mean, this is the best we've had.", "I mean, this is the best we've had."),
    ("We were close, I mean very close, to winning.", "We were close, I mean very close, to winning."),
]


def words(text):
    return [w for w in re.sub(r"[^\w'%$.]+", " ", text.lower()).split() if w.strip(".")]


def only_removes(answer, source):
    have = Counter(w.strip(".") for w in words(source))
    need = Counter(w.strip(".") for w in words(answer))
    return bool(need) and all(have[w] >= n for w, n in need.items())


def has_marker(text):
    low = text.lower()
    return any(re.search(r"(?<![a-z])" + re.escape(m) + r"(?![a-z])", low) for m in MARKERS)


def ask(text):
    messages = [{"role": "system", "content": SYSTEM}]
    for q, a in SHOTS:
        messages += [{"role": "user", "content": q}, {"role": "assistant", "content": a}]
    messages.append({"role": "user", "content": text})
    body = json.dumps({"messages": messages, "temperature": 0, "max_tokens": 120}).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions", body,
                                 {"Content-Type": "application/json"})
    start = time.perf_counter()
    with urllib.request.urlopen(req, timeout=120) as r:
        reply = json.load(r)["choices"][0]["message"]["content"]
    return reply.strip().strip('"').splitlines()[0].strip() if reply.strip() else "", time.perf_counter() - start


def serve(repo):
    log = open(HERE / ".server.log", "w")
    proc = subprocess.Popen(["llama-server", "-hf", repo, "--port", str(PORT), "-c", "4096",
                             "--no-webui"], stdout=log, stderr=subprocess.STDOUT)
    deadline = time.time() + 1800  # first run downloads the weights
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(f"llama-server exited; see {HERE / '.server.log'}")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
                if json.load(r).get("status") == "ok":
                    return proc
        except Exception:
            pass
        time.sleep(2)
    proc.kill()
    raise RuntimeError("llama-server never became ready")


def evaluate(key, cases, rules):
    proc = serve(MODELS[key])
    try:
        ask("Warm up, I mean warm up.")  # first call pays for graph setup
        tally, times, rejected, rows = defaultdict(lambda: [0, 0]), [], 0, []
        for case, fallback in zip(cases, rules):
            text = case["input"]
            if has_marker(text):
                answer, secs = ask(text)
                times.append(secs)
                ok = only_removes(answer, text)
                final = answer if ok else fallback
                rejected += not ok
            else:
                answer, ok, final = text, True, text
            passed = final == case["expected"]
            tally[case["category"]][0] += passed
            tally[case["category"]][1] += 1
            rows.append({**case, "answer": answer, "accepted": ok, "final": final, "pass": passed})
        return tally, times, rejected, rows
    finally:
        proc.terminate()
        proc.wait()


def main():
    cases = [json.loads(l) for l in (HERE / "self_corrections.jsonl").read_text().splitlines() if l]
    rules = json.loads((HERE / ".rules_output.json").read_text())
    report = {}
    for key in sys.argv[1:] or list(MODELS):
        tally, times, rejected, rows = evaluate(key, cases, rules)
        total = sum(p for p, _ in tally.values())
        print(f"\n== {key}: {total}/{len(cases)}  "
              f"(rejected {rejected}, median {statistics.median(times)*1000:.0f} ms, "
              f"max {max(times)*1000:.0f} ms)")
        for cat, (p, n) in sorted(tally.items()):
            print(f"   {cat}: {p}/{n}")
        for r in rows:
            if not r["pass"]:
                tag = "" if r["accepted"] else "  [rejected → rules]"
                print(f"   ✗ {r['input']}\n       model    {r['answer']}{tag}\n       expected {r['expected']}")
        report[key] = rows
    (HERE / ".llm_eval_results.json").write_text(json.dumps(report, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
