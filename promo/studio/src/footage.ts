import type { Shape } from "./components/Crop";

/**
 * The real screen recordings in public/footage (cleaned: denoise, 2× Lanczos,
 * light sharpen, 30 fps). Sizes are the coordinate space that crops, SHAPES
 * and SignOffNote use, in source pixels; times are seconds into the file.
 * How they were recorded: scripts/promo/README.md and promo/README.md.
 */
export const FOOTAGE = {
  /**
   * Live preview: small pill streaming the words, the cleaned text landing in a note. Its voice is
   * voice/benchmark-passage-jessica.mp3 laid `voiceOffset` s late (measured by cross-correlation).
   */
  livePreview: { src: "footage/live-preview.mp4", w: 1040, h: 780, pillCloses: 27.65, textLands: 28.15, voiceOffset: 0.45 },
  /**
   * live-preview.mp4 at 28.4 s, the pasted paragraph in the note, as a still: hold on this,
   * never on a frozen video (Studio's preview reloads a <Freeze>d video at its first frame).
   */
  livePreviewLanded: { src: "footage/live-preview-landed.png", w: 1040, h: 780 },
  /**
   * The Large pill alone (2026-10-15, scripts/promo/pilltake.swift): 2× Retina, lossless master in
   * promo/raw/pill-large-take.mov. The same voice starts `voiceAt` s in; its words show `lag` s after
   * they are spoken; the key is held until every word is up. `pill` is the pill's body in its pixels.
   */
  pillLarge: {
    src: "footage/pill-large.mp4",
    w: 1820,
    h: 192,
    voiceAt: 1.342,
    lag: 2.85,
    pill: { x: 65, y: 120, w: 1675, h: 61, r: 30.5 },
  },
  /** TYPE in the same 4:3 frame: the Lisbon message. Tab takes "take" at 21.97 s, "you think!" at 27.77 s. */
  typeSmall: { src: "footage/type-small.mp4", w: 1040, h: 780, tabTake: 21.97, tabThink: 27.77 },
  /** Talk, full screen: the notch pill at the top. */
  talkHero: { src: "footage/talk-hero.mp4", w: 2560, h: 1440 },
  /** The finished Lisbon note (end of type-small), the still SignOffNote draws on. */
  noteSignoffBase: { src: "footage/note-signoff-base.png", w: 1040, h: 780 },
} as const;

/** Source sizes, for Crop's srcSize: the 1040×780 recordings and talk-hero. */
export const LP = { w: FOOTAGE.livePreview.w, h: FOOTAGE.livePreview.h };
export const TH = { w: FOOTAGE.talkHero.w, h: FOOTAGE.talkHero.h };

/**
 * The real UI shapes in each recording (source pixels), measured from the
 * frames. Masking to these drops the recording's own backdrop and shadow, so
 * no off-black rectangle shows against ours.
 */
export const SHAPES = {
  // live-preview.mp4 / type-small.mp4 (1040×780): the Notes window and the pill.
  lpWindow: { x: 20, y: 16, w: 999, h: 661, r: 24 },
  lpPill: { x: 79, y: 706, w: 883, h: 59, r: 29.5 },
  // talk-hero.mp4 (2560×1440): the notch pill, hanging from the top edge.
  notch: { x: 1000, y: -40, w: 560, h: 99, r: 30 },
} satisfies Record<string, Shape>;

/** AI framing shots (Higgsfield, Kling 3.0 Pro), public/shots. People only frame the product. */
export const SHOTS = {
  /** Talking to the laptop, 16:9. */
  talking: "shots/shot-a-v2.mp4",
  /** Hands typing, 16:9. */
  typing: "shots/shot-b-v2.mp4",
  /** Vertical hook, 9:16. */
  vertical: "shots/shot-v.mp4",
} as const;
