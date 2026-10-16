import React, { createContext, useContext } from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { color, font } from "../brand/tokens";
import { clamp } from "../lib/anim";

/**
 * The smallest font size allowed, in frame pixels. 0 (the default) changes
 * nothing; the website copies set it so labels and small print survive being
 * shown at about a quarter size (videos/website). Read it with `useMinText()`
 * wherever a size could fall below it.
 */
export const MinText = createContext(0);
export const useMinText = () => useContext(MinText);
/** `size`, raised to the minimum when one is set. */
export const useLegible = (size: number) => Math.max(size, useMinText());

/** Small uppercase section label with the on-air dot. */
export const Label: React.FC<{ text: string; style?: React.CSSProperties; size?: number }> = ({ text, style, size: asked = 26 }) => {
  const size = useLegible(asked);
  return (
  <div
    style={{
      position: "absolute",
      display: "flex",
      alignItems: "center",
      gap: size * 0.45,
      fontFamily: font.body,
      fontWeight: 600,
      fontSize: size,
      letterSpacing: "0.12em",
      textTransform: "uppercase",
      color: color.walnut,
      ...style,
    }}
  >
    <span style={{ width: size * 0.45, height: size * 0.45, borderRadius: size, background: color.onAir }} />
    {text}
  </div>
  );
};

/** Big display line, one accent phrase in on-air red. Rises in at frame `at` of its parent. */
export const Headline: React.FC<{
  text: string;
  accent?: string;
  at?: number;
  size: number;
  style?: React.CSSProperties;
  align?: "left" | "center";
}> = ({ text, accent, at = 0, size, style, align = "left" }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - at, fps, config: { damping: 200 } });
  const parts = accent && text.includes(accent) ? text.split(accent) : [text];
  return (
    <div
      style={{
        position: "absolute",
        fontFamily: font.display,
        fontWeight: 800,
        fontStretch: "112%",
        letterSpacing: "-0.02em",
        fontSize: size,
        lineHeight: 1.02,
        color: color.ink,
        textAlign: align,
        textWrap: "balance",
        opacity: p,
        transform: `translateY(${(1 - p) * 24}px)`,
        ...style,
      }}
    >
      {parts.length === 2 ? (
        <>
          {parts[0]}
          <span style={{ color: color.onAir }}>{accent}</span>
          {parts[1]}
        </>
      ) : (
        text
      )}
    </div>
  );
};

/** The round brand dot from the PUSHTYPE wordmark, sized to the type next to it. */
export const BrandDot: React.FC<{ size: number }> = ({ size }) => (
  <span
    style={{
      display: "inline-block",
      width: size / 7,
      height: size / 7,
      borderRadius: size,
      background: color.onAir,
      marginLeft: size * 0.08,
      verticalAlign: "middle",
      transform: `translateY(-${size * 0.04}px)`,
    }}
  />
);

// MARK: Word-timed captions (vertical)

export type CapLine = { words: [string, number][]; until: number; accent?: string[] };

/** Burned-in caption: words appear as spoken; accent words in red. Times in seconds of the video. */
export const WordCaptions: React.FC<{ lines: CapLine[]; style: React.CSSProperties; size: number }> = ({ lines, style, size }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = f / fps;
  const line = lines.find((l) => t >= l.words[0][1] - 0.05 && t < l.until);
  if (!line) return null;
  const out = interpolate(t, [line.until - 0.15, line.until], [1, 0], clamp);
  return (
    <div
      style={{
        position: "absolute",
        fontFamily: font.display,
        fontWeight: 800,
        fontStretch: "112%",
        letterSpacing: "-0.02em",
        fontSize: size,
        lineHeight: 1.04,
        color: color.ink,
        textWrap: "balance",
        opacity: out,
        textShadow: "0 4px 24px rgba(0,0,0,0.55)",
        ...style,
      }}
    >
      {line.words.map(([w, at], i) => {
        const p = interpolate(t, [at - 0.05, at + 0.08], [0, 1], clamp);
        return (
          <span key={i} style={{ opacity: 0.18 + 0.82 * p, color: line.accent?.includes(w) ? color.onAir : undefined }}>
            {w}{" "}
          </span>
        );
      })}
    </div>
  );
};
