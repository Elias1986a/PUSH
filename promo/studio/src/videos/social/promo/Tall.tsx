import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { color, font } from "../../../brand/tokens";
import { s } from "../../../lib/time";
import { lerp, mixRect } from "../../../lib/anim";
import { FOOTAGE, LP, SHAPES, SHOTS, TH } from "../../../footage";
import {
  CapLine,
  CloudIcon,
  Crop,
  EndCard,
  FullShot,
  Glow,
  Headline,
  KeyChip,
  Label,
  LockIcon,
  Meter,
  MinText,
  PillTake,
  pillPushIn,
  PriceStack,
  Scene,
  useLegible,
  WordCaptions,
} from "../../../components";
import { Redline, SignOffNote, WordsToCloud } from "./beats";
import type { PromoProps } from "./Wide";

/**
 * 9:16 cut, 28.5 s. Built for phones. Everything that matters sits inside
 * the centre 4:5 area (y 285 to 1635), so Meta's in-feed crop loses nothing,
 * and clear of TikTok/Reels UI (bottom 420 px, right 120 px): text and key
 * visuals stay within x 60 to 960, y 340 to 1500. Promo4x5 is this frame
 * shifted up 285 px.
 */
const AT = { V1: 0.0, V2: 5.1, J: 8.0, V3: 14.1, V4: 19.9, V5: 23.4 };
const LP_J_FROM = 13.2;
const LP_RELEASE_FROM = 27.55;
const TS_B_FROM = 26.55; // "you" "think!" taken at 27.77 s → plays under "hit Tab"

const at = (k: keyof typeof AT, words: [string, number][]): [string, number][] => words.map(([w, t]) => [w, AT[k] + t]);

const CAPTIONS: CapLine[] = [
  { words: at("V1", [["Your", 0.0], ["dictation", 0.22], ["app", 0.78], ["sends", 1.04], ["your", 1.36], ["voice", 1.56], ["to", 1.82], ["the", 2.04], ["cloud.", 2.18]]), until: 3.15, accent: ["cloud."] },
  { words: at("V1", [["And", 2.56], ["bills", 3.22], ["you", 3.5], ["monthly", 3.72], ["for", 3.98], ["it.", 4.4]]), until: 5.0, accent: ["monthly"] },
  { words: at("J", [["the", 0.22], ["new", 0.3], ["build", 0.52], ["loads", 0.76], ["in", 1.1], ["15.2", 1.3], ["seconds.", 2.0]]), until: 11.2, accent: ["15.2"] },
  { words: at("J", [["I", 3.26], ["mean,", 3.32], ["1.52", 3.68], ["seconds.", 4.42]]), until: 13.25, accent: ["1.52"] },
  { words: at("V3", [["Talk", 0.0], ["messy.", 0.48], ["Get", 1.46], ["clean", 1.58], ["text.", 1.9]]), until: 16.95, accent: ["clean", "text."] },
  { words: at("V3", [["Then", 2.96], ["hit", 3.02], ["Tab", 3.22], ["and", 3.6], ["it", 3.94], ["finishes", 4.08], ["your", 4.42], ["sentence.", 4.7]]), until: 19.75, accent: ["Tab"] },
  { words: at("V4", [["It", 0.0], ["learns", 0.32], ["how", 0.66], ["you", 0.94], ["write.", 1.12]]), until: 21.75, accent: ["you"] },
  { words: at("V4", [["We", 1.94], ["never", 2.08], ["see", 2.42], ["it.", 2.74]]), until: 23.3, accent: ["never"] },
];

export const Tall: React.FC<PromoProps> = ({ web = false }) => (
  <MinText.Provider value={web ? 40 : 0}>
  <AbsoluteFill style={{ background: color.studio, fontFamily: font.body }}>
    <Glow />

    <Scene at={0} until={5.25} fade={0}>
      <Hook />
    </Scene>
    <Scene at={5.0} until={8.05}>
      <LocalBeat />
    </Scene>
    <Scene at={7.95} until={13.3} fade={4}>
      <LiveDictation />
    </Scene>
    <Scene at={13.25} until={14.55} fade={3}>
      <Release />
    </Scene>
    <Scene at={14.45} until={16.15} fade={4}>
      <RedlineBeat />
    </Scene>
    <Scene at={16.1} until={19.85} fade={4}>
      <TypeBeat />
    </Scene>
    <Scene at={19.8} until={23.45}>
      <LearnBeat />
    </Scene>
    <Scene at={23.35} until={26.1}>
      <PriceStack vertical yearsFrom={s(-0.6)} slamAt={s(0.1)} onceAt={s(0.95)} />
    </Scene>
    <Scene at={26.0} until={28.5}>
      <EndCard vertical />
    </Scene>

    <WordCaptions lines={CAPTIONS} size={76} style={{ left: 80, top: 370, width: 880 }} />

    <Sequence from={s(AT.V1)}><Audio src={staticFile("vo/promo/9x16/V1_hook.wav")} /></Sequence>
    <Sequence from={s(AT.V2)}><Audio src={staticFile("vo/promo/9x16/V2_local.wav")} /></Sequence>
    <Sequence from={s(AT.J)}><Audio src={staticFile("vo/promo/9x16/J_dictation_messy.wav")} volume={0.95} /></Sequence>
    <Sequence from={s(AT.V3)}><Audio src={staticFile("vo/promo/9x16/V3_talk_type.wav")} /></Sequence>
    <Sequence from={s(AT.V4)}><Audio src={staticFile("vo/promo/9x16/V4_learns.wav")} /></Sequence>
    <Sequence from={s(AT.V5)}><Audio src={staticFile("vo/promo/9x16/V5_price_end.wav")} /></Sequence>
    <Audio
      src={staticFile("music/music_loop_9x16.mp3")}
      startFrom={s(1.5)}
      volume={(f) =>
        interpolate(f, [0, s(0.2), s(26.6), s(26.9), s(27.8), s(28.5)], [0, 0.16, 0.16, 0.32, 0.32, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        })
      }
    />
  </AbsoluteFill>
  </MinText.Provider>
);

const Hook: React.FC = () => {
  const f = useCurrentFrame();
  const push = lerp(f, [0, s(5.2)], [1.0, 1.07], false);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ transform: `scale(${push})` }}>
        <FullShot src={SHOTS.vertical} dim={0.2} />
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(to bottom, rgba(14,14,16,0.85) 0%, rgba(14,14,16,0.2) 40%, rgba(14,14,16,0) 60%)" }} />
      <CloudIcon size={220} style={{ left: 760, top: 560, opacity: lerp(f, [s(1.6), s(2.2)], [0, 1]) }} />
      <WordsToCloud origin={{ x: 620, y: 1400 }} target={{ x: 870, y: 640 }} startAt={s(1.3)} every={6} travel={s(1.6)} size={36} />
      <Meter label="Subscription dictation" value="$12/mo" size={96} at={s(3.65)} style={{ left: 120, top: 1230 }} />
    </AbsoluteFill>
  );
};

const LocalBeat: React.FC = () => {
  const f = useCurrentFrame();
  const lockIn = lerp(f, [s(1.9), s(2.3)], [0, 1]);
  const pillIn = lerp(f, [s(1.9), s(2.4)], [0, 1]);
  return (
    <AbsoluteFill>
      <WordsToCloud origin={{ x: 540, y: 1100 }} target={{ x: 860, y: 640 }} startAt={0} every={3} travel={s(1.2)} size={36} reverse count={6} />
      <div style={{ opacity: pillIn }}>
        <Crop src={FOOTAGE.talkHero.src} from={6} crop={{ x: 947, y: 0, w: 666, h: 79 }} srcSize={TH} box={{ left: 90, top: 640, width: 900, height: 107 }} shapes={[SHAPES.notch]} />
      </div>
      <div style={{ opacity: lockIn, transform: `scale(${0.7 + 0.3 * lockIn})` }}>
        <LockIcon size={110} style={{ left: 485, top: 820 }} stroke={color.onAir} />
      </div>
      <Headline text="Every word stays on your Mac." accent="on your Mac." at={s(0.15)} size={100} style={{ left: 80, top: 1000, width: 920 }} align="center" />
    </AbsoluteFill>
  );
};

const LiveDictation: React.FC = () => {
  const f = useCurrentFrame();
  // Window full width; then push in on the pill for the correction.
  const t = lerp(f, [s(2.4), s(3.4)], [0, 1]);
  const crop = mixRect({ x: 0, y: 0, w: 1040, h: 780 }, pillPushIn(900), t);
  const width = 900;
  const box = { left: 90, top: 1095 - (width * crop.h) / crop.w / 2, width, height: (width * crop.h) / crop.w };
  return (
    <AbsoluteFill>
      <Label text="What she said" style={{ left: 80, top: 640 }} size={30} />
      <Crop src={FOOTAGE.livePreview.src} from={LP_J_FROM - 0.05} crop={crop} srcSize={LP} box={box} shapes={[SHAPES.lpWindow]} />
      <PillTake crop={crop} box={box} voiceFrom={LP_J_FROM - 0.05 - FOOTAGE.livePreview.voiceOffset} />
      <KeyChip text="⌥ hold" down size={36} style={{ left: 520, top: 622 }} />
    </AbsoluteFill>
  );
};

const Release: React.FC = () => {
  const f = useCurrentFrame();
  const releaseAt = s(27.65 - LP_RELEASE_FROM);
  const crop = { x: 30, y: 190, w: 980, h: 280 };
  const width = 900;
  return (
    <AbsoluteFill>
      <Label text="What it typed" style={{ left: 80, top: 640 }} size={30} />
      <Crop
        src={FOOTAGE.livePreview.src}
        from={LP_RELEASE_FROM}
        crop={crop}
        srcSize={LP}
        box={{ left: 90, top: 730, width, height: (width * crop.h) / crop.w }}
        card
      />
      <KeyChip text={f < releaseAt ? "⌥ hold" : "⌥ let go"} down={f < releaseAt} size={36} style={{ left: 520, top: 622 }} />
    </AbsoluteFill>
  );
};

const RedlineBeat: React.FC = () => (
  <AbsoluteFill>
    <Redline size={62} width={880} style={{ left: 80, top: 700 }} strikeUm={s(0.05)} strikeFix={s(0.3)} collapse={s(1.05)} />
  </AbsoluteFill>
);

const TypeBeat: React.FC = () => {
  const f = useCurrentFrame();
  // Local 0 = 16.1 s. Tab taken at 27.77 s src → 1.22 s local = 17.32 s ("hit Tab").
  const tab = s(27.77 - TS_B_FROM);
  const crop = { x: 40, y: 381, w: 560, h: 48 };
  const width = 900;
  return (
    <AbsoluteFill>
      <Label text="TYPE" style={{ left: 80, top: 640 }} size={30} />
      <Crop src={FOOTAGE.typeSmall.src} from={TS_B_FROM} crop={crop} srcSize={LP} box={{ left: 90, top: 730, width, height: (width * crop.h) / crop.w }} card />
      <KeyChip text="Tab" down={f >= tab && f < tab + 6} size={72} style={{ left: 430, top: 940 }} />
    </AbsoluteFill>
  );
};

const LearnBeat: React.FC = () => {
  const f = useCurrentFrame();
  // Local 0 = 19.8 s; V4 at 19.9.
  const crop = { x: 30, y: 440, w: 560, h: 200 };
  const width = 900;
  const scale = width / crop.w;
  const box = { left: 90, top: 700, width, height: width * (crop.h / crop.w) };
  const lock = lerp(f, [s(2.0), s(2.3)], [0, 1]);
  const small = useLegible(28);
  return (
    <AbsoluteFill>
      <Label text="TYPE · learns you" style={{ left: 80, top: 640 }} size={30} />
      <div style={{ position: "absolute", ...box, overflow: "hidden", borderRadius: 22, border: "1px solid rgba(255,255,255,0.16)", background: color.noteBg, boxShadow: "0 0 26px rgba(255,255,255,0.06), 0 30px 70px rgba(0,0,0,0.6)" }}>
        <div style={{ position: "absolute", left: -crop.x * scale, top: -crop.y * scale, transform: `scale(${scale})`, transformOrigin: "0 0" }}>
          <SignOffNote typeAt={s(0.25)} ghostAt={s(0.6)} tabAt={s(1.3)} />
        </div>
      </div>
      <KeyChip text="Tab" down={f >= s(1.3) && f < s(1.5)} size={60} style={{ left: 80, top: 1120 }} />
      <div style={{ position: "absolute", left: 300, top: 1130, display: "flex", alignItems: "center", gap: 18, opacity: lock }}>
        <div style={{ position: "relative", width: 60, height: 60 }}>
          <LockIcon size={60} stroke={color.onAir} />
        </div>
        <div style={{ fontFamily: font.display, fontWeight: 800, fontStretch: "112%", fontSize: 46, color: color.ink }}>On your Mac.</div>
      </div>
      <div style={{ position: "absolute", left: 300, top: 1210, fontFamily: font.body, fontSize: small, color: color.muted, opacity: lock }}>
        Learning is opt-in.
      </div>
    </AbsoluteFill>
  );
};
