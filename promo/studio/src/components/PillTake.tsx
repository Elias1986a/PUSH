import React from "react";
import { OffthreadVideo, staticFile } from "remotion";
import { FOOTAGE, SHAPES } from "../footage";
import type { Box, Rect } from "../lib/anim";
import { s } from "../lib/time";
import { LIFT, RIM } from "./Crop";

/**
 * The sharp Large-pill recording drawn where live-preview.mp4's own (soft,
 * Small) pill sits. Pass the same `crop` and `box` as the Crop of the window it
 * belongs to, and leave SHAPES.lpPill out of that Crop's shapes. It is scaled
 * to the old pill's width, so it fits the window shot and stays sharp in a
 * push-in. Push in on its right end, where new words arrive, and keep the
 * take's pixels at ≤ ~1.4× (`PILL_ZOOM`) so it stays sharp; when the crop
 * cuts the pill's left end, that end fades out instead of stopping flat.
 * - `voiceFrom`: the voice file's time at frame 0 of the parent sequence.
 * - `trail`: how long after a word is spoken it shows (the real lag is ~2.85 s;
 *   0.5 s matches the rest of the promo).
 */
/**
 * A push-in crop (live-preview pixels) on the pill's right end that shows the
 * take at `zoom`× its own pixels in a `frameWidth`-wide box. `h` is the crop's
 * height in live-preview pixels.
 */
export function pillPushIn(frameWidth: number, zoom = 1.4, h = 40): Rect {
  const slot = SHAPES.lpPill;
  const w = (frameWidth * (slot.w / FOOTAGE.pillLarge.pill.w)) / zoom;
  return { x: slot.x + slot.w + 8 - w, y: slot.y + slot.h / 2 - h / 2, w, h };
}

export const PillTake: React.FC<{ crop: Rect; box: Box; voiceFrom: number; trail?: number }> = ({ crop, box, voiceFrom, trail = 0.5 }) => {
  const P = FOOTAGE.pillLarge;
  const slot = SHAPES.lpPill;
  const k = slot.w / P.pill.w; // take pixels → live-preview pixels
  const z = box.width / crop.w; // live-preview pixels → frame pixels
  const scale = k * z; // take pixels → frame pixels
  const pillH = P.pill.h * k;
  const pill: React.CSSProperties = {
    position: "absolute",
    left: (slot.x - crop.x) * z,
    top: (slot.y + slot.h / 2 - pillH / 2 - crop.y) * z,
    width: slot.w * z,
    height: pillH * z,
    borderRadius: P.pill.r * scale,
  };
  const from = voiceFrom + P.voiceAt + P.lag - trail;
  const cut = Math.min(1, Math.max(0, (crop.x - slot.x) / 40));
  const fade = cut > 0 ? `linear-gradient(to right, transparent 0%, #000 ${cut * 14}%)` : undefined;
  return (
    <div style={{ position: "absolute", ...box, overflow: "hidden", maskImage: fade, WebkitMaskImage: fade }}>
      <div style={{ ...pill, boxShadow: RIM }} />
      <div style={{ ...pill, overflow: "hidden" }}>
        <OffthreadVideo
          src={staticFile(P.src)}
          startFrom={s(from)}
          muted
          style={{
            position: "absolute",
            left: -P.pill.x * scale,
            top: -P.pill.y * scale,
            width: P.w * scale,
            height: P.h * scale,
            maxWidth: "none",
            filter: LIFT,
          }}
        />
      </div>
    </div>
  );
};
