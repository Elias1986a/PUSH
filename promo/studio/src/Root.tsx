import React from "react";
import { Composition, Folder } from "remotion";
// Starts the font loads; loadFont holds rendering until they land.
import "./brand/tokens";
import { FPS, s } from "./lib/time";
import { DURATION_S, Explainer } from "./videos/explainer/Explainer";
import { Feed } from "./videos/promo/Feed";
import { Tall } from "./videos/promo/Tall";
import { Wide } from "./videos/promo/Wide";

/** Ad sizes (promo/PROMO-PLAYBOOK.md §1). */
const SIZE = {
  wide: { width: 1920, height: 1080 },
  feed: { width: 1080, height: 1350 },
  tall: { width: 1080, height: 1920 },
};

/** "Clean Pulse", ElevenLabs Music, from the user (2026-10-15). */
const music = "explainer-music.mp3";

// Every video registers here, one <Folder> per video, ids <Video><Format> (Promo16x9).
export const RemotionRoot: React.FC = () => (
  <>
    <Folder name="Promo">
      <Composition id="Promo16x9" component={Wide} durationInFrames={s(50)} fps={FPS} {...SIZE.wide} />
      <Composition id="Promo4x5" component={Feed} durationInFrames={s(28.5)} fps={FPS} {...SIZE.feed} />
      <Composition id="Promo9x16" component={Tall} durationInFrames={s(28.5)} fps={FPS} {...SIZE.tall} />
    </Folder>
    <Folder name="Explainer">
      <Composition
        id="Explainer16x9"
        component={Explainer}
        durationInFrames={s(DURATION_S)}
        fps={FPS}
        {...SIZE.wide}
        defaultProps={{ vertical: false, music }}
      />
      <Composition
        id="Explainer9x16"
        component={Explainer}
        durationInFrames={s(DURATION_S)}
        fps={FPS}
        {...SIZE.tall}
        defaultProps={{ vertical: true, music }}
      />
    </Folder>
  </>
);
