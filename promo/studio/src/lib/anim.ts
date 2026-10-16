import { Easing, interpolate, spring } from "remotion";

export type Box = { left: number; top: number; width: number; height: number };
export type Rect = { x: number; y: number; w: number; h: number };

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** interpolate(), clamped at both ends, eased in-out unless `ease` is false. */
export const lerp = (f: number, input: number[], output: number[], ease = true) =>
  interpolate(f, input, output, { ...clamp, easing: ease ? Easing.inOut(Easing.cubic) : undefined });

/** The house entrance: fade in while rising `distance` px, settling without bounce. Spread into a style. */
export const rise = (frame: number, fps: number, delay = 0, distance = 30) => {
  const p = spring({ frame: frame - delay, fps, config: { damping: 200 } });
  return { opacity: p, transform: `translateY(${(1 - p) * distance}px)` };
};

/** Interpolate between two crop rects (push-ins on a recording). */
export const mixRect = (a: Rect, b: Rect, t: number): Rect => ({
  x: a.x + (b.x - a.x) * t,
  y: a.y + (b.y - a.y) * t,
  w: a.w + (b.w - a.w) * t,
  h: a.h + (b.h - a.h) * t,
});
