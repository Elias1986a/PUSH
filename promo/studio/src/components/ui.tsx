import React from "react";
import { spring, useCurrentFrame, useVideoConfig } from "remotion";
import { color, font } from "../brand/tokens";
import { useLegible } from "./text";

/** A key that presses and lets go. */
export const KeyChip: React.FC<{ text: string; down: boolean; size?: number; style?: React.CSSProperties }> = ({
  text,
  down,
  size = 34,
  style,
}) => (
  <div
    style={{
      position: "absolute",
      padding: `${size * 0.4}px ${size * 0.75}px`,
      borderRadius: size * 0.47,
      fontFamily: font.mono,
      fontSize: size,
      whiteSpace: "nowrap",
      color: down ? "#1a0b08" : color.ink,
      background: down ? color.onAir : color.raised,
      border: `1px solid ${down ? color.onAir : color.chrome}`,
      boxShadow: down ? "0 1px 0 #8f2a1c" : "0 5px 0 #000",
      transform: `translateY(${down ? 4 : 0}px)`,
      ...style,
    }}
  >
    {text}
  </div>
);

/** A running price chip: $12/mo, then yearly totals. */
export const Meter: React.FC<{ label: string; value: string; size: number; style?: React.CSSProperties; at?: number }> = ({
  label,
  value,
  size,
  style,
  at = 0,
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: f - at, fps, config: { damping: 14, stiffness: 160 } });
  const labelSize = useLegible(size * 0.32);
  return (
    <div
      style={{
        position: "absolute",
        display: "flex",
        flexDirection: "column",
        gap: size * 0.12,
        padding: `${size * 0.35}px ${size * 0.6}px`,
        borderRadius: size * 0.4,
        background: "rgba(20,20,22,0.85)",
        border: `1px solid ${color.chrome}`,
        transform: `scale(${0.6 + 0.4 * p})`,
        opacity: Math.min(1, p * 1.5),
        ...style,
      }}
    >
      <div style={{ fontFamily: font.body, fontWeight: 600, fontSize: labelSize, letterSpacing: "0.1em", textTransform: "uppercase", color: color.muted }}>
        {label}
      </div>
      <div style={{ fontFamily: font.display, fontWeight: 800, fontStretch: "112%", fontSize: size, color: color.ink, lineHeight: 1 }}>
        {value}
      </div>
    </div>
  );
};

// MARK: Icons

export const CloudIcon: React.FC<{ size: number; style?: React.CSSProperties; tint?: string }> = ({ size, style, tint }) => (
  <svg width={size} height={size * 0.66} viewBox="0 0 120 80" style={{ position: "absolute", ...style }}>
    <path
      d="M30 74 H94 a22 22 0 0 0 2-44 a30 30 0 0 0-57-6 a22 22 0 0 0-9 50 Z"
      fill={tint ?? "rgba(239,237,232,0.12)"}
      stroke={color.ink}
      strokeOpacity={0.75}
      strokeWidth={3.5}
      strokeLinejoin="round"
    />
  </svg>
);

export const LockIcon: React.FC<{ size: number; style?: React.CSSProperties; stroke?: string }> = ({
  size,
  style,
  stroke = color.ink,
}) => (
  <svg width={size} height={size} viewBox="0 0 40 40" style={{ position: "absolute", ...style }}>
    <rect x="8" y="17" width="24" height="18" rx="4" fill="none" stroke={stroke} strokeWidth="3" />
    <path d="M13 17 v-5 a7 7 0 0 1 14 0 v5" fill="none" stroke={stroke} strokeWidth="3" />
    <circle cx="20" cy="26" r="2.4" fill={stroke} />
  </svg>
);
