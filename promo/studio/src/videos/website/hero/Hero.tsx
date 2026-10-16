import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { color, font } from "../../../brand/tokens";
import { rise } from "../../../lib/anim";
import { s } from "../../../lib/time";
import { FOOTAGE, LP, SHAPES } from "../../../footage";
import { BrandDot, Crop, Glow, Headline, KeyChip, LockIcon, Scene } from "../../../components";

/**
 * The website hero: a loop that autoplays muted beside the headline. It shows
 * at about a quarter of its size (≈500 px wide on a laptop, 330–480 px on a
 * phone), so it opens on the product, says one thing per beat, and keeps
 * every word ≥ ~50 px in the frame. Price and qualifiers live in the page copy,
 * where they can be read; this is not the ad (that is videos/social/promo).
 */
// A type, not an interface: Remotion needs props it can treat as Record<string, unknown>.
export type HeroProps = { format: "wide" | "feed" };

export const HERO_S = 21.5;

/** Scene times, seconds of the finished video. */
const T = {
  talk: [0, 6.0],
  lands: [5.9, 9.6],
  type: [9.5, 14.6],
  mac: [14.5, 17.8],
  end: [17.7, HERO_S],
} as const;

// Jessica's dictation (public/vo/promo/9x16/J_dictation_messy.wav) is
// live-preview.mp4 13.20–18.40 s: "…the new build loads in 15.2 seconds. I mean, 1.52 seconds."
const J_AT = 0.3;
const J_SRC = 13.2;
const LANDS_FROM = 27.55; // live-preview: pill closes 27.65 s, the text lands 28.07 s (0.5 s in)
const TYPE_FROM = 24.2; // type-small: "Let me| know", "what |you think", Tab takes "think!" at 27.77 s

/** Per-format layout. Wide is 1920×1080, feed (phones) 1080×1350. */
const L = {
  wide: {
    headline: { size: 116, style: { left: 110, top: 150, width: 1700 } },
    pill: { crop: { x: 400, y: 690, w: 600, h: 90 }, left: 80, top: 420, width: 1760 },
    line: { left: 210, top: 440, width: 1500 },
    key: { top: 760, size: 72 },
    lock: { top: 250, size: 150 },
    macHeadline: { size: 120, style: { left: 110, top: 460, width: 1700 } },
    word: 200,
    tagline: 84,
  },
  feed: {
    headline: { size: 100, style: { left: 80, top: 170, width: 920 } },
    pill: { crop: { x: 600, y: 690, w: 380, h: 90 }, left: 80, top: 560, width: 920 },
    line: { left: 80, top: 600, width: 920 },
    key: { top: 860, size: 64 },
    lock: { top: 330, size: 140 },
    macHeadline: { size: 100, style: { left: 80, top: 540, width: 920 } },
    word: 150,
    tagline: 72,
  },
};

/** The note's line "build loads in 1.52 seconds." once the dictation lands. */
const LANDED_LINE = { x: 52, y: 306, w: 410, h: 44 };
/** type-small's last line: "Let me know what you think!" wide, "know what you think!" on phones (bigger). */
const TYPED_LINE = { wide: { x: 165, y: 384, w: 430, h: 45 }, feed: { x: 277, y: 384, w: 317, h: 45 } };

export const Hero: React.FC<HeroProps> = ({ format }) => {
  const l = L[format];
  return (
    <AbsoluteFill style={{ background: color.studio, fontFamily: font.body }}>
      <Glow />

      {/* 1. Hold a key and talk: the real pill streaming her words. */}
      <Scene at={T.talk[0]} until={T.talk[1]}>
        <Headline text="Hold a key and talk." accent="talk." size={l.headline.size} style={l.headline.style} align="center" />
        {/* The pill runs on past the crop's left edge; fade it out rather than cut it. */}
        <AbsoluteFill style={{ maskImage: PILL_FADE, WebkitMaskImage: PILL_FADE }}>
          <Crop
            src={FOOTAGE.livePreview.src}
            from={J_SRC - J_AT}
            crop={l.pill.crop}
            srcSize={LP}
            box={{ left: l.pill.left, top: l.pill.top, width: l.pill.width, height: (l.pill.width * l.pill.crop.h) / l.pill.crop.w }}
            shapes={[SHAPES.lpPill]}
          />
        </AbsoluteFill>
        <CenteredKey text="⌥ hold" down top={l.key.top} size={l.key.size} />
      </Scene>

      {/* 2. Let go: the clean line lands, the correction made. */}
      <Scene at={T.lands[0]} until={T.lands[1]}>
        <Lands format={format} />
      </Scene>

      {/* 3. TYPE: gray suggestions while typing, Tab takes one. */}
      <Scene at={T.type[0]} until={T.type[1]}>
        <TypeBeat format={format} />
      </Scene>

      {/* 4. Privacy. */}
      <Scene at={T.mac[0]} until={T.mac[1]}>
        <MacBeat format={format} />
      </Scene>

      {/* 5. Wordmark; fades to the background so the loop restarts cleanly. */}
      <Scene at={T.end[0]} until={T.end[1]} fade={12}>
        <EndBeat format={format} />
      </Scene>

      <Sequence from={s(J_AT)}>
        <Audio src={staticFile("vo/promo/9x16/J_dictation_messy.wav")} volume={0.95} />
      </Sequence>
      <Audio
        src={staticFile("music/music_loop_16x9.mp3")}
        volume={(f) =>
          // Under her voice, then up a little; out by the loop point.
          interpolate(f, [0, s(0.3), s(5.5), s(6.0), s(20.6), s(HERO_S)], [0, 0.12, 0.12, 0.22, 0.22, 0], {
            extrapolateLeft: "clamp",
            extrapolateRight: "clamp",
          })
        }
      />
    </AbsoluteFill>
  );
};

const PILL_FADE = "linear-gradient(to right, transparent 3%, #000 16%)";

/** A KeyChip centred horizontally at `top`. */
const CenteredKey: React.FC<{ text: string; down: boolean; top: number; size: number }> = ({ text, down, top, size }) => (
  <div style={{ position: "absolute", left: 0, right: 0, top, display: "flex", justifyContent: "center" }}>
    <KeyChip text={text} down={down} size={size} style={{ position: "relative" }} />
  </div>
);

const Lands: React.FC<HeroProps> = ({ format }) => {
  const f = useCurrentFrame();
  const l = L[format];
  const released = f >= s(27.65 - LANDS_FROM);
  // The card comes up with the text, so no empty box waits for it.
  const landed = s(28.07 - LANDS_FROM);
  const cardIn = interpolate(f, [landed - 3, landed + 2], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <Headline text="It types what you meant." accent="meant." size={l.headline.size} style={l.headline.style} align="center" />
      <AbsoluteFill style={{ opacity: cardIn }}>
        <Crop
          src={FOOTAGE.livePreview.src}
          from={LANDS_FROM}
          crop={LANDED_LINE}
          srcSize={LP}
          box={{ ...l.line, height: (l.line.width * LANDED_LINE.h) / LANDED_LINE.w }}
          card
        />
      </AbsoluteFill>
      <CenteredKey text={released ? "⌥ let go" : "⌥ hold"} down={!released} top={l.key.top} size={l.key.size} />
    </AbsoluteFill>
  );
};

const TypeBeat: React.FC<HeroProps> = ({ format }) => {
  const f = useCurrentFrame();
  const l = L[format];
  const tab = s(27.77 - TYPE_FROM);
  const line = TYPED_LINE[format];
  return (
    <AbsoluteFill>
      <Headline text="Start typing. Tab finishes it." accent="Tab" size={l.headline.size} style={l.headline.style} align="center" />
      <Crop
        src={FOOTAGE.typeSmall.src}
        from={TYPE_FROM}
        crop={line}
        srcSize={LP}
        box={{ ...l.line, height: (l.line.width * line.h) / line.w }}
        card
      />
      <CenteredKey text="Tab" down={f >= tab && f < tab + 6} top={l.key.top} size={l.key.size} />
    </AbsoluteFill>
  );
};

const MacBeat: React.FC<HeroProps> = ({ format }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const l = L[format];
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", left: 0, right: 0, top: l.lock.top, height: l.lock.size, ...rise(f, fps) }}>
        <LockIcon size={l.lock.size} style={{ left: `calc(50% - ${l.lock.size / 2}px)` }} stroke={color.onAir} />
      </div>
      <Headline
        text="Your voice and words stay on your Mac."
        accent="on your Mac."
        at={6}
        size={l.macHeadline.size}
        style={l.macHeadline.style}
        align="center"
      />
    </AbsoluteFill>
  );
};

const EndBeat: React.FC<HeroProps> = ({ format }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const l = L[format];
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", textAlign: "center", gap: 40 }}>
      <div style={{ fontFamily: font.display, fontWeight: 800, fontStretch: "112%", letterSpacing: "-0.02em", fontSize: l.word, color: color.ink, ...rise(f, fps) }}>
        PUSHTYPE
        <BrandDot size={l.word} />
      </div>
      <div style={{ fontFamily: font.display, fontWeight: 800, fontSize: l.tagline, lineHeight: 1.05, color: color.ink, ...rise(f, fps, 8) }}>
        PUSH to talk.{format === "feed" ? <br /> : " "}Tab to TYPE.
      </div>
    </AbsoluteFill>
  );
};
