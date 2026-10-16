import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { color, font } from "../../../brand/tokens";
import { clamp, lerp } from "../../../lib/anim";
import { FOOTAGE } from "../../../footage";

// Promo-only pieces: their words are baked in, so they are not shared components.

// MARK: Words drifting to the cloud (hook)

const SNIPPETS = ["move the review", "Tuesday 4:30", "$5 million", "Zurich office", "final numbers", "Hey Jess,", "Lisbon", "37%"];

/** Fragments of what you said float up from `origin` toward `target`. */
export const WordsToCloud: React.FC<{
  origin: { x: number; y: number };
  target: { x: number; y: number };
  startAt: number;
  every: number;
  travel: number;
  size: number;
  reverse?: boolean;
  count?: number;
}> = ({ origin, target, startAt, every, travel, size, reverse = false, count = 8 }) => {
  const f = useCurrentFrame();
  return (
    <AbsoluteFill>
      {SNIPPETS.slice(0, count).map((w, i) => {
        const t0 = startAt + i * every;
        let p = interpolate(f, [t0, t0 + travel], [0, 1], { ...clamp, easing: Easing.inOut(Easing.quad) });
        if (f < t0) return null;
        if (reverse) p = 1 - p;
        const a = reverse ? target : origin;
        const b = reverse ? origin : target;
        const q = reverse ? 1 - p : p;
        const x = a.x + (b.x - a.x) * q + Math.sin(i * 1.7 + q * 3) * 40 * (1 - Math.abs(0.5 - q) * 2);
        const y = a.y + (b.y - a.y) * q;
        const opacity = interpolate(q, [0, 0.12, 0.8, 1], [0, 1, 1, 0]);
        const sc = interpolate(q, [0, 1], [1, 0.55]);
        return (
          <div
            key={w}
            style={{
              position: "absolute",
              left: x,
              top: y,
              transform: `translate(-50%,-50%) scale(${sc})`,
              opacity,
              fontFamily: font.body,
              fontWeight: 600,
              fontSize: size,
              color: color.ink,
              padding: `${size * 0.25}px ${size * 0.55}px`,
              borderRadius: size,
              background: "rgba(20,20,22,0.72)",
              border: `1px solid ${color.chrome}`,
              whiteSpace: "nowrap",
            }}
          >
            {w}
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

// MARK: Redline (raw dictation → clean text)

type Tok = { t: string; kind?: "cut" | "fix" };
const RAW: Tok[] = [
  { t: "Um,", kind: "cut" },
  { t: "we've spent 37% of the $5 million budget, and the new build loads in" },
  { t: "15.2 seconds. I mean,", kind: "cut" },
  { t: "1.52", kind: "fix" },
  { t: "seconds." },
];

/**
 * The raw line strikes through where the narrator names each fix, then the cut
 * words fold away and the clean sentence settles. Times are frames in the parent.
 */
export const Redline: React.FC<{
  size: number;
  width: number;
  style?: React.CSSProperties;
  strikeUm: number;
  strikeFix: number;
  collapse: number;
  align?: "left" | "center";
}> = ({ size, width, style, strikeUm, strikeFix, collapse, align = "left" }) => {
  const f = useCurrentFrame();
  const cutIndex = (i: number) => (i === 0 ? strikeUm : strikeFix);
  const fold = lerp(f, [collapse, collapse + 14], [0, 1]);
  return (
    <div
      style={{
        position: "absolute",
        width,
        fontFamily: font.display,
        fontWeight: 700,
        fontStretch: "105%",
        fontSize: size,
        lineHeight: 1.18,
        color: color.ink,
        textAlign: align,
        ...style,
      }}
    >
      {RAW.map((tok, i) => {
        if (tok.kind === "cut") {
          const at = cutIndex(i);
          const strike = lerp(f, [at, at + 8], [0, 1]);
          return (
            <span
              key={i}
              style={{
                position: "relative",
                display: "inline-block",
                color: interpolate(strike, [0, 1], [0, 1]) > 0.5 ? color.muted : color.ink,
                opacity: 1 - fold,
                maxWidth: `${(1 - fold) * 100}%`,
                whiteSpace: "nowrap",
                overflow: "hidden",
                verticalAlign: "bottom",
                marginRight: `${(1 - fold) * 0.28}em`,
                fontSize: `${100 - fold * 100}%`,
              }}
            >
              {tok.t}
              <span
                style={{
                  position: "absolute",
                  left: 0,
                  top: "54%",
                  height: Math.max(3, size * 0.07),
                  width: `${strike * 100}%`,
                  background: color.onAir,
                  borderRadius: 4,
                }}
              />
            </span>
          );
        }
        if (tok.kind === "fix") {
          const lit = lerp(f, [strikeFix + 6, strikeFix + 14], [0, 1]);
          return (
            <span
              key={i}
              style={{
                display: "inline-block",
                marginRight: "0.28em",
                padding: "0 0.12em",
                borderRadius: 8,
                background: `rgba(255,90,69,${0.22 * lit})`,
                color: lit > 0.5 ? color.peach : color.ink,
              }}
            >
              {tok.t}
            </span>
          );
        }
        return (
          <span key={i} style={{ marginRight: "0.28em" }}>
            {tok.t}
          </span>
        );
      })}
    </div>
  );
};

// MARK: Sign-off (TYPE learns you), drawn over the last frame of type-small.mp4

/**
 * The finished Lisbon note, then a new line: "Ta" typed, a gray suggestion
 * "lk soon," + "Maya" from her own past sign-offs, Tab takes it.
 * Geometry is in the 1040×780 source frame; the parent scales it.
 */
export const SignOffNote: React.FC<{ typeAt: number; ghostAt: number; tabAt: number }> = ({ typeAt, ghostAt, tabAt }) => {
  const f = useCurrentFrame();
  const typed = f < typeAt ? "" : f < typeAt + 5 ? "T" : "Ta";
  const ghost = f >= ghostAt && f < tabAt;
  const taken = f >= tabAt;
  const blink = Math.floor(f / 16) % 2 === 0 || (f > typeAt - 4 && f < tabAt + 20);
  const lineY = (n: number) => 461 + n * 38; // top of the nth line after "Can't wait to see you!"
  const textStyle: React.CSSProperties = {
    position: "absolute",
    left: 67,
    fontFamily: font.notes,
    fontSize: 26.5,
    lineHeight: "33px",
    letterSpacing: "-0.005em",
    whiteSpace: "pre",
  };
  const caretLine = taken ? 3 : f >= typeAt - 12 ? 2 : 0;
  const caretText = taken ? "Maya" : typed;
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: 1040, height: 780 }}>
      <Img src={staticFile(FOOTAGE.noteSignoffBase.src)} style={{ position: "absolute", left: 0, top: 0, width: 1040, height: 780 }} />
      {f >= typeAt - 12 ? (
        <>
          <div style={{ ...textStyle, top: lineY(2), color: color.noteText }}>
            {typed}
            {ghost || taken ? <span style={{ color: taken ? color.noteText : color.noteGhost }}>lk soon,</span> : null}
          </div>
          {ghost || taken ? (
            <div style={{ ...textStyle, top: lineY(3), color: taken ? color.noteText : color.noteGhost }}>Maya</div>
          ) : null}
        </>
      ) : null}
      {blink ? (
        <Caret
          left={caretLine === 0 ? 374 : 67 + measure(caretText) + (caretLine === 2 && (ghost || taken) && !taken ? 0 : 0)}
          top={caretLine === 0 ? 461 : lineY(caretLine)}
        />
      ) : null}
    </div>
  );
};

const Caret: React.FC<{ left: number; top: number }> = ({ left, top }) => (
  <div style={{ position: "absolute", left: left + 1, top, width: 4, height: 33, borderRadius: 2, background: color.caret }} />
);

/** Rough advance widths for Inter 26.5px (only the few strings we draw). */
function measure(text: string) {
  const w: Record<string, number> = { "": 0, T: 15.5, Ta: 30.5, Maya: 64 };
  return w[text] ?? text.length * 14;
}
