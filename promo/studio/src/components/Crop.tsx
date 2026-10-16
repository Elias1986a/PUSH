import React from "react";
import { Img, OffthreadVideo, staticFile } from "remotion";
import { color } from "../brand/tokens";
import type { Box, Rect } from "../lib/anim";
import { s } from "../lib/time";

/** A rounded rect in a recording's source pixels: a window, the pill, the notch. */

export type Shape = { x: number; y: number; w: number; h: number; r: number };

function shapeMask(shapes: Shape[], srcSize: { w: number; h: number }) {
  const rects = shapes.map((r) => `<rect x='${r.x}' y='${r.y}' width='${r.w}' height='${r.h}' rx='${r.r}' fill='white'/>`).join("");
  const svg = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 ${srcSize.w} ${srcSize.h}' preserveAspectRatio='none'><filter id='b'><feGaussianBlur stdDeviation='0.8'/></filter><g filter='url(#b)'>${rects}</g></svg>`;
  return `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`;
}

/**
 * Part of a recording: `crop` (source pixels) scaled to fill `box`.
 * - `shapes`: keep only those UI shapes (window, pill, notch); our background shows everywhere else.
 * - `card`: a crop inside a window, framed as a zoomed card with crisp edges.
 */
export const Crop: React.FC<{
  src: string;
  from: number;
  rate?: number;
  crop: Rect;
  box: Box;
  srcSize: { w: number; h: number };
  radius?: number;
  feather?: number;
  still?: boolean;
  shapes?: Shape[];
  card?: boolean;
}> = ({ src, from, rate = 1, crop, box, srcSize, radius = 18, feather = 40, still = false, shapes, card = false }) => {
  const scale = box.width / crop.w;
  const fx = Math.min(feather, box.width * 0.08);
  const fy = Math.min(feather, box.height * 0.2);
  const edgeMask =
    !shapes && !card && feather > 0
      ? `linear-gradient(to right, transparent, #000 ${fx}px, #000 calc(100% - ${fx}px), transparent),
         linear-gradient(to bottom, transparent, #000 ${fy}px, #000 calc(100% - ${fy}px), transparent)`
      : undefined;
  const sm = shapes ? shapeMask(shapes, srcSize) : undefined;
  const mediaBox: React.CSSProperties = {
    position: "absolute",
    width: srcSize.w * scale,
    height: srcSize.h * scale,
    left: -crop.x * scale,
    top: -crop.y * scale,
    WebkitMaskImage: sm,
    maskImage: sm,
    WebkitMaskSize: "100% 100%",
    maskSize: "100% 100%",
    // Lift the recordings a step above the near-black background.
    filter: "brightness(1.14) contrast(1.04)",
  };
  const fill: React.CSSProperties = { position: "absolute", inset: 0, width: "100%", height: "100%", maxWidth: "none" };
  // Rim light, drawn as plain box-shadows on rounded rects behind each UI shape
  // (much cheaper to render than CSS drop-shadow filters on video).
  const rims = (shapes ?? [])
    .filter((r) => r.x < crop.x + crop.w && r.x + r.w > crop.x && r.y < crop.y + crop.h && r.y + r.h > crop.y)
    .map((r, i) => (
    <div
      key={i}
      style={{
        position: "absolute",
        left: (r.x - crop.x) * scale,
        top: (r.y - crop.y) * scale,
        width: r.w * scale,
        height: r.h * scale,
        borderRadius: r.r * scale,
        boxShadow: "0 0 0 1px rgba(255,255,255,0.28), 0 0 22px rgba(255,255,255,0.07), 0 24px 40px rgba(0,0,0,0.6)",
      }}
    />
  ));
  return (
    <div style={{ position: "absolute", ...box }}>
      {shapes ? <div style={{ position: "absolute", inset: 0, overflow: "hidden" }}>{rims}</div> : null}
      <div
        style={{
          position: "absolute",
          inset: 0,
          overflow: "hidden",
          borderRadius: shapes ? 0 : card ? Math.max(radius, 22) : radius,
          border: card ? "1px solid rgba(255,255,255,0.16)" : undefined,
          background: card ? color.noteBg : undefined,
          boxShadow: card ? "0 0 26px rgba(255,255,255,0.06), 0 30px 70px rgba(0,0,0,0.6)" : undefined,
          WebkitMaskImage: edgeMask,
          WebkitMaskComposite: "source-in",
          maskImage: edgeMask,
          maskComposite: "intersect",
        }}
      >
        <div style={mediaBox}>
          {still ? (
            <Img src={staticFile(src)} style={fill} />
          ) : (
            <OffthreadVideo src={staticFile(src)} startFrom={s(from)} playbackRate={rate} muted style={fill} />
          )}
        </div>
      </div>
    </div>
  );
};
