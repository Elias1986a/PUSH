import React from "react";
import { AbsoluteFill, Audio, Sequence, interpolate, staticFile, useCurrentFrame } from "remotion";
import { color, font } from "../../../brand/tokens";
import { s } from "../../../lib/time";
import { lerp, mixRect } from "../../../lib/anim";
import { FOOTAGE, LP, SHAPES, SHOTS, TH } from "../../../footage";
import {
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
} from "../../../components";
import { Redline, SignOffNote, WordsToCloud } from "./beats";

/**
 * 16:9 cut, 50 s. Every time is seconds of the finished video, from the cut VO
 * lines (public/vo/promo/16x9) placed at VO_AT. Source times are seconds into each recording.
 */
export const VO_AT = {
  N1: 0.0,
  N2: 5.6,
  N3: 10.2,
  J: 12.5,
  N4: 23.4,
  N5: 29.4,
  N6: 33.7,
  N7: 39.9,
  N8: 44.5,
};

// live-preview.mp4: J is cut from 8.70 s; the pill closes at 27.65 s, text lands 28.07 s.
const LP_J_FROM = 8.7;
const LP_RELEASE_FROM = 27.45;
// type-small.mp4: Tab takes "take" at 21.97 s; "you" "think!" at 27.77 s.
const TS_A_FROM = 20.0;
const TS_A_RATE = 1.2;
const TS_B_FROM = 26.6;

const WIN_SCALE = 1.3;
const winBox = { left: (1920 - LP.w * WIN_SCALE) / 2, top: (1080 - LP.h * WIN_SCALE) / 2, width: LP.w * WIN_SCALE, height: LP.h * WIN_SCALE };
const full = { x: 0, y: 0, w: LP.w, h: LP.h };

// A type, not an interface: Remotion needs props it can treat as Record<string, unknown>.
export type PromoProps = {
  /**
   * The website copy (videos/website): same cut, but small text raised to a
   * readable minimum and the hook captioned, since it plays muted at about a
   * quarter of its size.
   */
  web?: boolean;
};

export const Wide: React.FC<PromoProps> = ({ web = false }) => (
  <MinText.Provider value={web ? 44 : 0}>
  <AbsoluteFill style={{ background: color.studio, fontFamily: font.body }}>
    <Glow />

    {/* 1. Hook: her voice goes to the cloud, and the bill follows. */}
    <Scene at={0} until={5.25} fade={0}>
      <Hook web={web} />
    </Scene>

    {/* 2. PUSHTYPE keeps it on your Mac: words fall back, the real pill lights up. */}
    <Scene at={5.0} until={10.25}>
      <LocalBeat />
    </Scene>

    {/* 3. Hold a key: the notch pill listening, ⌥ held. */}
    <Scene at={10.0} until={12.6}>
      <HoldKey />
    </Scene>

    {/* 4. Jessica dictates: live pill streaming her messy words. */}
    <Scene at={12.45} until={22.25} fade={4}>
      <LiveDictation web={web} />
    </Scene>

    {/* 5. Release: the clean paragraph lands in the note. */}
    <Scene at={22.2} until={23.5} fade={3}>
      <Release />
    </Scene>

    {/* 6. Redline: what got cut and fixed. */}
    <Scene at={23.4} until={29.3}>
      <RedlineBeat />
    </Scene>

    {/* 7. TYPE: hands, then Tab finishing real sentences. */}
    <Scene at={29.2} until={29.85} fade={3}>
      <FullShot src={SHOTS.typing} from={0.6} />
    </Scene>
    <Scene at={29.8} until={33.75} fade={3}>
      <TypeBeat />
    </Scene>

    {/* 8. It learns you: her own sign-off, suggested. */}
    <Scene at={33.65} until={40.0}>
      <LearnBeat />
    </Scene>

    {/* 9. Price. */}
    <Scene at={39.9} until={44.55}>
      <PriceStack vertical={false} yearsFrom={s(0.5)} slamAt={s(2.38)} onceAt={s(2.84)} />
    </Scene>

    {/* 10. End card. */}
    <Scene at={44.45} until={50}>
      <EndCard vertical={false} />
    </Scene>

    <Voice />
  </AbsoluteFill>
  </MinText.Provider>
);

const Voice: React.FC = () => (
  <>
    {(["N1", "N2", "N3", "N4", "N5", "N6", "N7", "N8"] as const).map((k) => (
      <Sequence key={k} from={s(VO_AT[k])}>
        <Audio src={staticFile(`vo/promo/16x9/${fileFor(k)}.wav`)} />
      </Sequence>
    ))}
    <Sequence from={s(VO_AT.J)}>
      <Audio src={staticFile("vo/promo/16x9/J_dictation_messy.wav")} volume={0.95} />
    </Sequence>
    <Audio
      src={staticFile("music/music_loop_16x9.mp3")}
      volume={(f) =>
        interpolate(f, [0, s(0.3), s(47.9), s(48.3), s(49.2), s(50)], [0, 0.16, 0.16, 0.32, 0.32, 0], {
          extrapolateLeft: "clamp",
          extrapolateRight: "clamp",
        })
      }
    />
  </>
);

function fileFor(k: string) {
  return {
    N1: "N1_hook",
    N2: "N2_local",
    N3: "N3_holdkey",
    N4: "N4_cleanup",
    N5: "N5_type",
    N6: "N6_learns",
    N7: "N7_price",
    N8: "N8_endcard",
  }[k];
}

// MARK: Scenes

const Hook: React.FC<{ web: boolean }> = ({ web }) => {
  const f = useCurrentFrame();
  const push = lerp(f, [0, s(5.2)], [1.0, 1.08], false);
  const cloudIn = lerp(f, [s(1.6), s(2.2)], [0, 1]);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ transform: `scale(${push})` }}>
        <FullShot src={SHOTS.talking} dim={0.25} />
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(to right, rgba(14,14,16,0) 35%, rgba(14,14,16,0.7) 100%)" }} />
      <div style={{ opacity: cloudIn }}>
        <CloudIcon size={260} style={{ left: 1520, top: 70 }} />
        <Label text="Their servers" style={{ left: web ? 1450 : 1530, top: 250 }} size={22} />
      </div>
      <WordsToCloud origin={{ x: 1080, y: 640 }} target={{ x: 1650, y: 160 }} startAt={s(1.4)} every={6} travel={s(1.6)} size={30} />
      <Meter label="Subscription dictation" value="$12/mo" size={80} at={s(3.4)} style={{ left: web ? 1130 : 1290, top: 760 }} />
      {web ? (
        // N1's two sentences, for the muted website copy (pauses measured in N1_hook.wav).
        <>
          <AbsoluteFill style={{ background: "linear-gradient(to top, rgba(8,8,10,0.8) 0%, rgba(8,8,10,0) 45%)" }} />
          <Sequence from={s(0.1)} durationInFrames={s(3.0)} layout="none">
            <Headline text="Most dictation apps send your voice to the cloud." accent="the cloud." size={76} style={{ left: 90, top: 790, width: 1000 }} />
          </Sequence>
          <Sequence from={s(3.15)} layout="none">
            <Headline text="Then charge you every month for it." accent="every month" size={76} style={{ left: 90, top: 790, width: 1000 }} />
          </Sequence>
        </>
      ) : null}
    </AbsoluteFill>
  );
};

const LocalBeat: React.FC = () => {
  const f = useCurrentFrame();
  // Local frame 0 = 5.0 s. N2 at 5.6 s.
  const pillIn = lerp(f, [s(3.5), s(4.1)], [0, 1]);
  const lockIn = lerp(f, [s(3.3), s(3.7)], [0, 1]);
  const pill = { x: 947, y: 0, w: 666, h: 79 };
  return (
    <AbsoluteFill>
      <CloudIcon size={200} style={{ left: 1560, top: 90, opacity: lerp(f, [0, s(1.4)], [0.8, 0.15]) }} />
      <WordsToCloud origin={{ x: 960, y: 640 }} target={{ x: 1660, y: 160 }} startAt={0} every={4} travel={s(1.4)} size={30} reverse count={6} />
      <Headline text="PUSHTYPE keeps every word on your Mac." accent="on your Mac." at={s(0.6)} size={96} style={{ left: 160, top: 470, width: 1600 }} align="center" />
      <div style={{ opacity: lockIn, transform: `scale(${0.7 + 0.3 * lockIn})` }}>
        <LockIcon size={88} style={{ left: 916, top: 330 }} stroke={color.onAir} />
      </div>
      <div style={{ opacity: pillIn }}>
        <Crop src={FOOTAGE.talkHero.src} from={6} crop={pill} srcSize={TH} box={{ left: 560, top: 0, width: 800, height: 95 }} shapes={[SHAPES.notch]} />
      </div>
    </AbsoluteFill>
  );
};

const HoldKey: React.FC = () => {
  const f = useCurrentFrame();
  const pill = { x: 947, y: 0, w: 666, h: 79 };
  const down = f > s(0.35);
  return (
    <AbsoluteFill>
      <Crop src={FOOTAGE.talkHero.src} from={10} crop={pill} srcSize={TH} box={{ left: 410, top: 0, width: 1100, height: 130 }} shapes={[SHAPES.notch]} />
      <Label text="Talk" style={{ left: 90, top: 60 }} />
      <KeyChip text={down ? "⌥ hold" : "⌥"} down={down} size={64} style={{ left: 800, top: 380 }} />
      <Headline text="Hold a key, and just talk." accent="talk." at={s(0.25)} size={96} style={{ left: 160, top: 640, width: 1600 }} align="center" />
    </AbsoluteFill>
  );
};

const LiveDictation: React.FC<{ web: boolean }> = ({ web }) => {
  const f = useCurrentFrame();
  // Local 0 = 12.45 s; push in on the pill for the correction ("15.2… I mean, 1.52").
  const t = lerp(f, [s(1.0), s(2.2)], [0, 1]);
  const crop = mixRect(full, pillPushIn(1760), t);
  const width = winBox.width + (1760 - winBox.width) * t;
  const box = { left: (1920 - width) / 2, top: 0, width, height: width * (crop.h / crop.w) };
  box.top = (1080 - box.height) / 2 + 40 * t;
  return (
    <AbsoluteFill>
      <Crop src={FOOTAGE.livePreview.src} from={LP_J_FROM - 0.05} crop={crop} srcSize={LP} box={box} shapes={[SHAPES.lpWindow]} />
      <PillTake crop={crop} box={box} voiceFrom={LP_J_FROM - 0.05 - FOOTAGE.livePreview.voiceOffset} />
      {/* On the website copy the bigger label would sit on the window; it comes in with the push. */}
      <div style={{ opacity: web ? t : 1 }}>
        <Label text="Talk · live preview" style={{ left: 90, top: 60 }} />
        <KeyChip text="⌥ hold" down size={40} style={{ left: 90, top: 120 }} />
      </div>
    </AbsoluteFill>
  );
};

const Release: React.FC = () => {
  const f = useCurrentFrame();
  const releaseAt = s(27.65 - LP_RELEASE_FROM);
  return (
    <AbsoluteFill>
      <Crop src={FOOTAGE.livePreview.src} from={LP_RELEASE_FROM} crop={full} srcSize={LP} box={winBox} shapes={[SHAPES.lpWindow]} />
      <Label text="Talk · live preview" style={{ left: 90, top: 60 }} />
      <KeyChip text={f < releaseAt ? "⌥ hold" : "⌥ let go"} down={f < releaseAt} size={40} style={{ left: 90, top: 120 }} />
    </AbsoluteFill>
  );
};

const RedlineBeat: React.FC = () => {
  const f = useCurrentFrame();
  // Local 0 = 23.4 s = N4 start. "um's" 0.8, "corrections" 2.04, "clean text" 3.32.
  const noteIn = lerp(f, [s(3.3), s(3.8)], [0, 1]);
  return (
    <AbsoluteFill>
      <Label text="What she said" style={{ left: 160, top: 150, opacity: 1 - noteIn }} />
      <Label text="What it typed" style={{ left: 160, top: 150, opacity: noteIn }} />
      <Redline size={64} width={1600} style={{ left: 160, top: 230 }} strikeUm={s(0.75)} strikeFix={s(1.9)} collapse={s(3.2)} />
      <Headline text="Clean text, wherever you're typing." accent="Clean text," at={s(3.4)} size={72} style={{ left: 160, top: 760, width: 1600 }} />
    </AbsoluteFill>
  );
};

const TypeBeat: React.FC = () => {
  const f = useCurrentFrame();
  // Local 0 = 29.8 s. Segment A to 1.8 s (Tab at 21.97 s src = 1.64 s), B after (Tab at 27.77 = 2.97 s).
  const bAt = s(1.8);
  const inB = f >= bAt;
  const tabA = s((21.97 - TS_A_FROM) / TS_A_RATE);
  const tabB = bAt + s(27.77 - TS_B_FROM);
  const keyDown = (f >= tabA && f < tabA + 6) || (f >= tabB && f < tabB + 6);
  const lineA = { x: 40, y: 308, w: 960, h: 150 };
  const lineB = { x: 40, y: 346, w: 960, h: 150 };
  const crop = inB ? lineB : lineA;
  const width = 1700;
  const box = { left: 110, top: 300, width, height: width * (crop.h / crop.w) };
  return (
    <AbsoluteFill>
      <Label text="TYPE" style={{ left: 110, top: 150 }} />
      {!inB ? (
        <Crop src={FOOTAGE.typeSmall.src} from={TS_A_FROM} rate={TS_A_RATE} crop={crop} srcSize={LP} box={box} card />
      ) : (
        <Sequence from={bAt} layout="none">
          <Crop src={FOOTAGE.typeSmall.src} from={TS_B_FROM} crop={crop} srcSize={LP} box={box} card />
        </Sequence>
      )}
      <Headline text="It finishes your sentence." accent="finishes" at={s(0)} size={72} style={{ left: 110, top: 720, width: 1100 }} />
      <KeyChip text="Tab" down={keyDown} size={56} style={{ left: 1560, top: 730 }} />
    </AbsoluteFill>
  );
};

const LearnBeat: React.FC = () => {
  const f = useCurrentFrame();
  // Local 0 = 33.65 s; N6 at 33.7: "writes like you" ~2.1 s, "Learned on your Mac" 3.45, "Never sent to us" 4.8.
  const zoom = lerp(f, [s(0.2), s(1.4)], [0, 1]);
  const crop = mixRect({ x: 0, y: 0, w: 1040, h: 780 }, { x: 34, y: 250, w: 980, h: 400 }, zoom);
  const width = 1250;
  const box = { left: 90, top: (1080 - width * (crop.h / crop.w)) / 2, width, height: width * (crop.h / crop.w) };
  const scale = box.width / crop.w;
  const chip = lerp(f, [s(3.4), s(3.8)], [0, 1]);
  const lock = lerp(f, [s(4.75), s(5.1)], [0, 1]);
  const small = useLegible(24);
  return (
    <AbsoluteFill>
      <div style={{ position: "absolute", ...box, overflow: "hidden", borderRadius: 22, border: "1px solid rgba(255,255,255,0.16)", background: color.noteBg, boxShadow: "0 0 26px rgba(255,255,255,0.06), 0 30px 70px rgba(0,0,0,0.6)" }}>
        <div style={{ position: "absolute", left: -crop.x * scale, top: -crop.y * scale, transform: `scale(${scale})`, transformOrigin: "0 0" }}>
          <SignOffNote typeAt={s(0.9)} ghostAt={s(1.35)} tabAt={s(2.25)} />
        </div>
      </div>
      <Label text="TYPE · learns you" style={{ left: 90, top: 60 }} />
      <KeyChip text="Tab" down={f >= s(2.25) && f < s(2.45)} size={48} style={{ left: 1430, top: 330 }} />
      <div style={{ position: "absolute", left: 1430, top: 470, width: 420, opacity: chip, transform: `translateY(${(1 - chip) * 16}px)` }}>
        <div style={{ fontFamily: font.display, fontWeight: 800, fontStretch: "112%", fontSize: 64, lineHeight: 1.02, color: color.ink }}>
          Learned on <span style={{ color: color.onAir }}>your Mac.</span>
        </div>
      </div>
      <div style={{ position: "absolute", left: 1430, top: 650, width: 460, display: "flex", alignItems: "center", gap: 14, opacity: lock, whiteSpace: "nowrap" }}>
        <div style={{ position: "relative", width: 52, height: 52 }}>
          <LockIcon size={52} stroke={color.onAir} />
        </div>
        <div style={{ fontFamily: font.display, fontWeight: 800, fontStretch: "112%", fontSize: 42, color: color.ink }}>Never sent to us.</div>
      </div>
      <div style={{ position: "absolute", left: 1430, top: 740, fontFamily: font.body, fontSize: small, color: color.muted, opacity: lock }}>
        Learning is opt-in.
      </div>
    </AbsoluteFill>
  );
};
