import React from "react";
import { AbsoluteFill, OffthreadVideo, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { color } from "../brand/tokens";
import { clamp } from "../lib/anim";
import { s } from "../lib/time";

/** A scene from `at` to `until` (seconds), with short fades. */
export const Scene: React.FC<{ at: number; until: number; fade?: number; children: React.ReactNode }> = ({
  at,
  until,
  fade = 5,
  children,
}) => {
  const from = s(at);
  const duration = s(until) - from;
  return (
    <Sequence from={from} durationInFrames={duration}>
      <Fade duration={duration} fade={fade}>
        {children}
      </Fade>
    </Sequence>
  );
};

const Fade: React.FC<{ duration: number; fade: number; children: React.ReactNode }> = ({ duration, fade, children }) => {
  const f = useCurrentFrame();
  const opacity = fade === 0 ? 1 : interpolate(f, [0, fade, duration - fade, duration], [0, 1, 1, 0], clamp);
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

/** The site's warm glow behind everything. */
export const Glow: React.FC = () => (
  <AbsoluteFill
    style={{
      background: `radial-gradient(60% 50% at 80% 100%, ${color.coral}22, transparent 70%),
                   radial-gradient(50% 45% at 10% 0%, ${color.violet}22, transparent 70%)`,
    }}
  />
);

/** Full-bleed generated shot (cover), slow drift. */
export const FullShot: React.FC<{ src: string; from?: number; dim?: number }> = ({ src, from = 0, dim = 0 }) => (
  <AbsoluteFill>
    <OffthreadVideo
      src={staticFile(src)}
      startFrom={s(from)}
      muted
      style={{ width: "100%", height: "100%", objectFit: "cover" }}
    />
    {dim > 0 ? <AbsoluteFill style={{ background: `rgba(10,10,12,${dim})` }} /> : null}
  </AbsoluteFill>
);
