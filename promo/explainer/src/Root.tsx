import React from "react";
import { Composition } from "remotion";
import { Explainer } from "./Explainer";
// theme.ts starts the font loads; loadFont holds rendering until they land.
import { DURATION_S, FPS } from "./theme";

/** "Clean Pulse", ElevenLabs Music, from the user (2026-10-15). */
const music = "explainer-music.mp3";

export const RemotionRoot: React.FC = () => (
  <>
    <Composition
      id="Explainer16x9"
      component={Explainer}
      durationInFrames={Math.round(DURATION_S * FPS)}
      fps={FPS}
      width={1920}
      height={1080}
      defaultProps={{ vertical: false, music }}
    />
    <Composition
      id="Explainer9x16"
      component={Explainer}
      durationInFrames={Math.round(DURATION_S * FPS)}
      fps={FPS}
      width={1080}
      height={1920}
      defaultProps={{ vertical: true, music }}
    />
  </>
);
