import React from "react";
import {
  AbsoluteFill,
  Audio,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { FPS, VO_OFFSET_S, color, font } from "./theme";

// Everything is timed in seconds of the finished video, from the voiceover
// (promo/voice/explainer-vo.mp3, second take, lines measured 2026-10-15) laid
// in at VO_OFFSET_S.
const s = (seconds: number) => Math.round(seconds * FPS);

/** Scene boundaries, in seconds of the finished video. */
const T = {
  hook: [0, 2.4],
  talk: [2.4, 6.4],
  hands: [6.4, 7.6],
  type: [7.6, 11.1],
  prompter: [11.1, 14.9],
  end: [14.9, 21],
} as const;

/** Where each real clip plays from (seconds into the source). */
const SRC = {
  // promo/talk-hero.mp4: real time. Text lands at 28.82 s; the key came up
  // ~0.35 s before. Played from 27.3 so the text lands ~1.5 s in and stays
  // on screen under "clean text".
  talkFrom: 27.3,
  talkRelease: 28.47,
  // promo/type-demo.mp4: "Should we rent a car or" → gray "take the metro?" →
  // Tab at 21.52 s, which plays at 9.92 s under the word "Tab".
  typeFrom: 19.2,
};

// A type, not an interface: Remotion's Composition needs props it can treat
// as Record<string, unknown>, which an interface never is.
export type ExplainerProps = {
  vertical: boolean;
  /** Optional music bed in public/audio. */
  music?: string;
};

export const Explainer: React.FC<ExplainerProps> = ({ vertical, music }) => {
  return (
    <AbsoluteFill style={{ background: color.studio, fontFamily: font.body }}>
      <Glow />
      <Scene range={T.hook}>
        <ShotScene vertical={vertical} src="shots/shot-a.mp4" label="Talk" />
      </Scene>
      <Scene range={T.talk}>
        <TalkScene vertical={vertical} />
      </Scene>
      <Scene range={T.hands}>
        <ShotScene vertical={vertical} src="shots/shot-b.mp4" label="TYPE" />
      </Scene>
      <Scene range={T.type}>
        <TypeScene vertical={vertical} />
      </Scene>
      <Scene range={T.prompter}>
        <ShotScene vertical={vertical} src="shots/shot-c.mp4" label="Teleprompter" />
      </Scene>
      <Scene range={T.end}>
        <EndCard vertical={vertical} />
      </Scene>

      <Captions vertical={vertical} />

      <Sequence from={s(VO_OFFSET_S)}>
        <Audio src={staticFile("audio/explainer-vo.mp3")} />
      </Sequence>
      {music ? (
        <Audio
          src={staticFile(`audio/${music}`)}
          volume={(f) =>
            // Under the voice ~12 dB down (measured in the mix), up for the
            // end card once the last line is out; the track's last chord
            // lands at 19 s, so it rings before the fade.
            interpolate(f, [0, s(0.4), s(17.2), s(17.8), s(19.6), s(21)], [0, 0.18, 0.18, 0.3, 0.3, 0], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            })
          }
        />
      ) : null}
    </AbsoluteFill>
  );
};

/** A scene with a short fade at each end. */
const Scene: React.FC<{ range: readonly [number, number]; children: React.ReactNode }> = ({ range, children }) => {
  const from = s(range[0]);
  const duration = s(range[1]) - from;
  return (
    <Sequence from={from} durationInFrames={duration}>
      <FadeInOut duration={duration}>{children}</FadeInOut>
    </Sequence>
  );
};

const FadeInOut: React.FC<{ duration: number; children: React.ReactNode }> = ({ duration, children }) => {
  const f = useCurrentFrame();
  const opacity = interpolate(f, [0, 5, duration - 5, duration], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return <AbsoluteFill style={{ opacity }}>{children}</AbsoluteFill>;
};

/** The site's warm glow behind everything. */
const Glow: React.FC = () => (
  <AbsoluteFill
    style={{
      background: `radial-gradient(60% 50% at 80% 100%, ${color.coral}22, transparent 70%),
                   radial-gradient(50% 45% at 10% 0%, ${color.violet}22, transparent 70%)`,
    }}
  />
);

// MARK: Layout

/** Where the media sits and where the caption goes, per format. */
function frameFor(vertical: boolean) {
  return vertical
    ? { media: { left: 60, top: 220, width: 960, height: 960 }, caption: { left: 70, top: 1250, width: 940 } }
    : { media: { left: 90, top: 90, width: 900, height: 900 }, caption: { left: 1060, top: 330, width: 780 } };
}

const Label: React.FC<{ text: string; style?: React.CSSProperties }> = ({ text, style }) => (
  <div
    style={{
      position: "absolute",
      display: "flex",
      alignItems: "center",
      gap: 12,
      fontFamily: font.body,
      fontWeight: 600,
      fontSize: 26,
      letterSpacing: "0.12em",
      textTransform: "uppercase",
      color: color.walnut,
      ...style,
    }}
  >
    <span style={{ width: 12, height: 12, borderRadius: 6, background: color.onAir }} />
    {text}
  </div>
);

const Card: React.FC<{ box: { left: number; top: number; width: number; height: number }; children: React.ReactNode }> = ({
  box,
  children,
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const scale = interpolate(spring({ frame: f, fps, config: { damping: 200 } }), [0, 1], [0.96, 1]);
  return (
    <div
      style={{
        position: "absolute",
        ...box,
        borderRadius: 28,
        overflow: "hidden",
        background: color.raised,
        boxShadow: "0 30px 80px rgba(0,0,0,0.55)",
        border: `1px solid ${color.chrome}`,
        transform: `scale(${scale})`,
      }}
    >
      {children}
    </div>
  );
};

// MARK: Scenes

/** A generated shot: square, in a card, with the feature's label. */
const ShotScene: React.FC<{ vertical: boolean; src: string; label: string }> = ({ vertical, src, label }) => {
  const { media, caption } = frameFor(vertical);
  return (
    <AbsoluteFill>
      <Card box={media}>
        <OffthreadVideo src={staticFile(src)} muted style={{ width: "100%", height: "100%", objectFit: "cover" }} />
      </Card>
      <Label text={label} style={{ left: caption.left, top: caption.top - 70 }} />
    </AbsoluteFill>
  );
};

/**
 * Part of a real recording: `crop` (fractions of the source frame) scaled to
 * fill `box`. Several crops of one clip can play together.
 */
const Crop: React.FC<{
  src: string;
  from: number;
  crop: { x: number; y: number; w: number; h: number };
  box: { left: number; top: number; width: number; height: number };
  srcSize?: { w: number; h: number };
  radius?: number;
  /** False for a crop that hangs from the frame's top edge, like the notch. */
  fadeTop?: boolean;
}> = ({ src, from, crop, box, srcSize = { w: 2560, h: 1440 }, radius = 22, fadeTop = true }) => {
  const scale = box.width / (crop.w * srcSize.w);
  // Feathered edges: the recording's black is not quite the background's, so a
  // hard-edged crop reads as a two-tone box. Faded at every edge, it melts in.
  const fx = Math.min(80, box.width * 0.06);
  const fy = Math.min(60, box.height * 0.22);
  const mask = `linear-gradient(to right, transparent, #000 ${fx}px, #000 calc(100% - ${fx}px), transparent),
                linear-gradient(to bottom, ${fadeTop ? "transparent" : "#000"}, #000 ${fy}px, #000 calc(100% - ${fy}px), transparent)`;
  return (
    <div
      style={{
        position: "absolute",
        ...box,
        overflow: "hidden",
        borderRadius: radius,
        WebkitMaskImage: mask,
        WebkitMaskComposite: "source-in",
        maskImage: mask,
        maskComposite: "intersect",
      }}
    >
      <OffthreadVideo
        src={staticFile(src)}
        startFrom={s(from)}
        muted
        style={{
          position: "absolute",
          width: srcSize.w * scale,
          height: srcSize.h * scale,
          left: -crop.x * srcSize.w * scale,
          top: -crop.y * srcSize.h * scale,
          maxWidth: "none",
        }}
      />
    </div>
  );
};

/** A key, drawn like the site's buttons, that presses and lets go. */
const KeyChip: React.FC<{ text: string; down: boolean; style?: React.CSSProperties }> = ({ text, down, style }) => (
  <div
    style={{
      position: "absolute",
      padding: "14px 26px",
      borderRadius: 16,
      fontFamily: font.mono,
      fontSize: 34,
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

/** `crop` (fractions of a 2560×1440 recording) placed at `left, top`, `width` wide. */
function boxFor(crop: { w: number; h: number }, left: number, top: number, width: number) {
  return { left, top, width, height: (width * (crop.h * 1440)) / (crop.w * 2560) };
}

const TalkScene: React.FC<{ vertical: boolean }> = ({ vertical }) => {
  const f = useCurrentFrame();
  const releaseAt = s(SRC.talkRelease - SRC.talkFrom);
  const down = f < releaseAt;
  const { caption } = frameFor(vertical);
  // The pill (top centre) and the note's first lines, cut from one recording.
  const pill = { x: 0.37, y: 0, w: 0.26, h: 0.055 };
  const text = vertical ? { x: 0.05, y: 0.225, w: 0.37, h: 0.2 } : { x: 0.05, y: 0.225, w: 0.62, h: 0.2 };
  // Hung from the top edge, where it lives on a Mac: under the notch.
  const pillBox = vertical ? boxFor(pill, 140, 0, 800) : boxFor(pill, 510, 0, 900);
  const textBox = vertical ? boxFor(text, 60, 470, 960) : boxFor(text, 90, 330, 1740);
  // The pill closes on release in the recording; its empty strip goes with it.
  const pillOpacity = interpolate(f, [releaseAt, releaseAt + 6], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill>
      <Label text="Talk" style={vertical ? { left: caption.left, top: 120 } : { left: 90, top: 60 }} />
      <div style={{ opacity: pillOpacity }}>
        <Crop src="media/talk-hero.mp4" from={SRC.talkFrom} crop={pill} box={pillBox} radius={0} fadeTop={false} />
      </div>
      <Crop src="media/talk-hero.mp4" from={SRC.talkFrom} crop={text} box={textBox} />
      <KeyChip
        text={down ? "⌥ hold" : "⌥ let go"}
        down={down}
        style={vertical ? { left: 70, top: 1080 } : { left: 90, top: 150 }}
      />
    </AbsoluteFill>
  );
};

const TypeScene: React.FC<{ vertical: boolean }> = ({ vertical }) => {
  const { caption } = frameFor(vertical);
  // The line where TYPE suggests "take the metro?" and Tab takes it.
  const text = vertical ? { x: 0.19, y: 0.344, w: 0.31, h: 0.046 } : { x: 0.06, y: 0.295, w: 0.56, h: 0.105 };
  const box = vertical ? boxFor(text, 40, 640, 1000) : boxFor(text, 90, 360, 1740);
  return (
    <AbsoluteFill>
      <Label text="TYPE" style={vertical ? { left: caption.left, top: 120 } : { left: 90, top: 60 }} />
      <Crop src="media/type-demo.mp4" from={SRC.typeFrom} crop={text} box={box} />
    </AbsoluteFill>
  );
};

const EndCard: React.FC<{ vertical: boolean }> = ({ vertical }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const rise = (delay: number) => {
    const p = spring({ frame: f - delay, fps, config: { damping: 200 } });
    return { opacity: p, transform: `translateY(${(1 - p) * 30}px)` };
  };
  const big = vertical ? 150 : 170;
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", textAlign: "center", gap: 36 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 18, ...rise(0) }}>
        <span
          style={{
            fontFamily: font.display,
            fontWeight: 800,
            fontStretch: "112%",
            letterSpacing: "-0.02em",
            fontSize: big,
            color: color.ink,
          }}
        >
          PUSHTYPE
        </span>
        <span style={{ width: big / 7, height: big / 7, borderRadius: big, background: color.onAir }} />
      </div>
      <div
        style={{
          fontFamily: font.display,
          fontWeight: 800,
          fontSize: vertical ? 64 : 60,
          lineHeight: 1.05,
          color: color.ink,
          ...rise(6),
        }}
      >
        PUSH to talk.{vertical ? <br /> : " "}Tab to TYPE.
      </div>
      <div style={{ fontFamily: font.body, fontSize: vertical ? 40 : 36, color: color.muted, ...rise(12) }}>
        Everything stays on your Mac.
      </div>
      <div style={{ fontFamily: font.mono, fontSize: vertical ? 40 : 34, color: color.onAir, marginTop: 20, ...rise(18) }}>
        pushtype.app
      </div>
    </AbsoluteFill>
  );
};

// MARK: Captions

/** The voiceover's words on screen, so the vertical cut works muted. */
const LINES: { text: string; accent?: string; at: number; until: number }[] = [
  { text: "Hold a key, and just talk.", accent: "talk.", at: 0.48, until: 2.4 },
  { text: "Clean text, right where you're typing.", accent: "Clean text,", at: 2.61, until: 6.4 },
  { text: "Start typing. It finishes your sentence.", accent: "finishes", at: 6.55, until: 9.3 },
  // The real Tab press in type-demo (21.52 s) plays at 9.92 s, under "Tab".
  { text: "Just press Tab to accept.", accent: "Tab", at: 9.38, until: 11.1 },
  { text: "On camera? The teleprompter automatically follows your voice.", accent: "teleprompter", at: 11.28, until: 14.9 },
];

const Captions: React.FC<{ vertical: boolean }> = ({ vertical }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = f / fps;
  const line = LINES.find((l) => t >= l.at && t < l.until);
  if (!line) return null;
  const local = f - s(line.at);
  const p = spring({ frame: local, fps, config: { damping: 200 } });
  const fadeOut = interpolate(f, [s(line.until) - 5, s(line.until)], [1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  // App scenes put the caption under the recording; shot scenes beside it.
  const onApp = (t >= T.talk[0] && t < T.talk[1]) || (t >= T.type[0] && t < T.type[1]);
  const pos = vertical
    ? { left: 70, top: 1250, width: 940 }
    : onApp
      ? { left: 90, top: 790, width: 1740 }
      : frameFor(false).caption;
  const words = line.text.split(" ");
  return (
    <div
      style={{
        position: "absolute",
        ...pos,
        fontFamily: font.display,
        fontWeight: 800,
        fontStretch: "112%",
        letterSpacing: "-0.02em",
        // Long lines a size down, so they wrap in three lines, not five.
        fontSize: vertical ? 92 : onApp ? 76 : line.text.length > 45 ? 70 : 84,
        lineHeight: 1.0,
        color: color.ink,
        opacity: p * fadeOut,
        transform: `translateY(${(1 - p) * 24}px)`,
        textWrap: "balance",
      }}
    >
      {words.map((w, i) => (
        <span key={i} style={{ color: line.accent?.split(" ").includes(w) ? color.onAir : undefined }}>
          {w}{" "}
        </span>
      ))}
    </div>
  );
};
