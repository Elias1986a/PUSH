import React from "react";
import { AbsoluteFill, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { color, font } from "../brand/tokens";
import { lerp, rise } from "../lib/anim";
import { BrandDot, useLegible } from "./text";

// MARK: End card

export const EndCard: React.FC<{ vertical: boolean }> = ({ vertical }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const up = (delay: number) => rise(f, fps, delay);
  const big = vertical ? 118 : 170;
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", textAlign: "center", gap: 36 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 18, ...up(0) }}>
        <span style={{ fontFamily: font.display, fontWeight: 800, fontStretch: "112%", letterSpacing: "-0.02em", fontSize: big, color: color.ink }}>
          PUSHTYPE
        </span>
        <span style={{ width: big / 7, height: big / 7, borderRadius: big, background: color.onAir }} />
      </div>
      <div style={{ fontFamily: font.display, fontWeight: 800, fontSize: vertical ? 64 : 60, lineHeight: 1.05, color: color.ink, ...up(8) }}>
        PUSH to talk.{vertical ? <br /> : " "}Tab to TYPE.
      </div>
      <div style={{ fontFamily: font.body, fontSize: vertical ? 40 : 36, color: color.muted, ...up(16) }}>
        Your words stay on your Mac.
      </div>
      <div style={{ fontFamily: font.mono, fontSize: vertical ? 46 : 40, color: color.onAir, marginTop: 20, ...up(24) }}>
        www.pushtype.app
      </div>
    </AbsoluteFill>
  );
};

// MARK: Price

export const PriceStack: React.FC<{ vertical: boolean; yearsFrom: number; slamAt: number; onceAt: number }> = ({
  vertical,
  yearsFrom,
  slamAt,
  onceAt,
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const yearsShown = f < yearsFrom ? 0 : Math.min(3, 1 + Math.floor((f - yearsFrom) / 12));
  const total = ["$12/mo", "$144", "$288", "$432"][yearsShown];
  const yearLabel = ["Subscription dictation", "Year 1", "Year 2", "Year 3"][yearsShown];
  const slam = spring({ frame: f - slamAt, fps, config: { damping: 12, stiffness: 180 } });
  const once = spring({ frame: f - onceAt, fps, config: { damping: 200 } });
  const strike = lerp(f, [slamAt - 2, slamAt + 6], [0, 1]);
  const big = vertical ? 200 : 210;
  const label = useLegible(vertical ? 34 : 30);
  const small = useLegible(vertical ? 28 : 24);
  return (
    <AbsoluteFill
      style={{
        flexDirection: vertical ? "column" : "row",
        justifyContent: "center",
        alignItems: "center",
        gap: vertical ? 90 : 140,
      }}
    >
      <div style={{ textAlign: "center", opacity: 1 - 0.55 * strike }}>
        <div style={{ fontFamily: font.body, fontWeight: 600, fontSize: label, letterSpacing: "0.12em", textTransform: "uppercase", color: color.muted }}>
          Subscription dictation · {yearLabel}
        </div>
        <div style={{ position: "relative", display: "inline-block", fontFamily: font.display, fontWeight: 800, fontStretch: "112%", fontSize: big * 0.7, color: color.muted, marginTop: 10 }}>
          {total}
          <span style={{ position: "absolute", left: -10, right: -10, top: "52%", height: 10, background: color.onAir, transform: `scaleX(${strike})`, transformOrigin: "left", borderRadius: 6 }} />
        </div>
      </div>
      <div style={{ textAlign: "center", transform: `scale(${0.4 + 0.6 * slam})`, opacity: Math.min(1, slam * 2) }}>
        <div style={{ fontFamily: font.body, fontWeight: 600, fontSize: label, letterSpacing: "0.12em", textTransform: "uppercase", color: color.walnut }}>
          PUSHTYPE
        </div>
        <div style={{ fontFamily: font.display, fontWeight: 900, fontStretch: "112%", fontSize: big, color: color.ink, lineHeight: 1 }}>
          $35<span style={{ opacity: once }}><BrandDot size={big} /></span>
        </div>
        <div style={{ fontFamily: font.display, fontWeight: 800, fontStretch: "112%", fontSize: big * 0.42, color: color.onAir, opacity: once, transform: `translateY(${(1 - once) * 20}px)` }}>
          Once.
        </div>
        <div style={{ fontFamily: font.body, fontSize: small, color: color.muted, marginTop: 16, opacity: once }}>
          Launch price · up to 3 Macs
        </div>
      </div>
    </AbsoluteFill>
  );
};
