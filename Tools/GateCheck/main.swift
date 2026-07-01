import Foundation
import SwiftLlama

// Phase 2 verification on the PATCHED vendored SwiftLlama (raw prompt + special
// tokens + newer llama.cpp source). Reproduces the POC's ENTITY/ORDINARY few-shot
// batched format that scored 10-11/12.

let modelPath = ("~/Library/Developer/SwiftPackages/PUSH-models/Qwen2.5-0.5B-Instruct-Q4_K_M.gguf" as NSString).expandingTildeInPath

let system = """
You decide, from sentence context, whether an ambiguous word is being used as \
the SPECIFIC ENTITY described, or as its ordinary everyday meaning. Names often \
sound like common words. Reply one line per candidate: "<number> ENTITY" or \
"<number> ORDINARY". Output only those lines.
"""

let fewShot: [(String, String)] = [
    ("Sentence: \"Please forward the email to Hammer.\"\nCandidate 1: \"Hammer\" (entity: a person named Hamer)", "1 ENTITY"),
    ("Sentence: \"He grabbed a hammer from the shed.\"\nCandidate 1: \"hammer\" (entity: a person named Hamer)", "1 ORDINARY"),
    ("Sentence: \"Ask Hammer and bring the hammer.\"\nCandidate 1: \"Hammer\" (entity: a person named Hamer)\nCandidate 2: \"hammer\" (entity: a person named Hamer)", "1 ENTITY\n2 ORDINARY"),
]

func userMsg(_ sentence: String, _ cands: [String]) -> String {
    var l = ["Sentence: \"\(sentence)\""]
    for (i, w) in cands.enumerated() { l.append("Candidate \(i+1): \"\(w)\" (entity: a person named Hamer)") }
    return l.joined(separator: "\n")
}

func messages(_ sentence: String, _ cands: [String]) -> [(role: String, content: String)] {
    var m: [(role: String, content: String)] = [("system", system)]
    for (u, a) in fewShot { m.append(("user", u)); m.append(("assistant", a)) }
    m.append(("user", userMsg(sentence, cands)))
    return m
}

let cases: [(String, String, [String])] = [
    ("E", "I emailed Hammer this morning.", ["Hammer"]),
    ("E", "Tell Hammer the ads are live.", ["Hammer"]),
    ("E", "This is from Hammer.", ["Hammer"]),
    ("E", "Hammer said hi to everyone.", ["Hammer"]),
    ("E", "I have a meeting with Hammer later today.", ["Hammer"]),
    ("O", "Pass me the hammer.", ["hammer"]),
    ("O", "I bought a new hammer.", ["hammer"]),
    ("O", "That hammer is really heavy.", ["hammer"]),
    ("O", "I went to the store and bought a hammer.", ["hammer"]),
    ("O", "Use a hammer to drive the nail.", ["hammer"]),
    ("E,O", "Hammer bought a hammer.", ["Hammer", "hammer"]),
    ("O,E", "Give the hammer to Hammer.", ["hammer", "Hammer"]),
]

func parse(_ out: String, _ n: Int) -> String {
    var v = [String](repeating: "O", count: n)
    for line in out.split(whereSeparator: \.isNewline) {
        let s = String(line)
        let digits = s.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
        guard let k = Int(digits), k >= 1, k <= n else { continue }
        if s.uppercased().contains("ENTITY") { v[k-1] = "E" }
    }
    return v.joined(separator: ",")
}

let config = Configuration(topK: 5, topP: 0.9, nCTX: 2048, temperature: 0.0, maxTokenCount: 24, stopTokens: ["<|im_end|>"])
guard let llama = try? SwiftLlama(modelPath: modelPath, modelConfiguration: config) else {
    print("FAILED to load model"); exit(1)
}

func judge(_ sentence: String, _ cands: [String]) async -> (String, String) {
    let prompt = await llama.formatChat(messages(sentence, cands), addAssistant: true)
    do {
        let out = try await llama.start(for: Prompt(type: .raw, userMessage: prompt))
        return (parse(out, cands.count), out)
    } catch {
        return (parse("", cands.count), "<ERR: \(error)>")
    }
}

// Show the exact templated prompt once, to confirm it matches llama-server.
let samplePrompt = await llama.formatChat(messages("I emailed Hammer today.", ["Hammer"]), addAssistant: true)
print("=== templated prompt ===\n\(samplePrompt)\n=== end ===")
_ = await judge("warm up", ["x"])

var pass = 0
var lats: [Double] = []
for (exp, sent, cands) in cases {
    let t0 = Date()
    let (got, raw) = await judge(sent, cands)
    let ms = Date().timeIntervalSince(t0) * 1000
    lats.append(ms)
    let ok = got == exp
    if ok { pass += 1 }
    print("\(ok ? "OK " : "XX ") \(sent.prefix(38).padding(toLength: 38, withPad: " ", startingAt: 0)) exp=\(exp) got=\(got) \(Int(ms))ms raw=[\(raw.replacingOccurrences(of: "\n", with: "|"))]")
}
let sorted = lats.dropFirst().sorted()
let med = sorted.isEmpty ? 0 : sorted[sorted.count/2]
let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count-1, Int(0.95*Double(sorted.count)))]
print("Accuracy: \(pass)/\(cases.count)  |  latency med=\(Int(med))ms p95=\(Int(p95))ms")
