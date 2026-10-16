import React from "react";
import { Composition, Folder } from "remotion";
// Starts the font loads; loadFont holds rendering until they land.
import "./brand/tokens";
import { FPS, s } from "./lib/time";
import { DURATION_S, Explainer } from "./videos/archive/explainer/Explainer";
import { Feed } from "./videos/social/promo/Feed";
import { Tall } from "./videos/social/promo/Tall";
import { Wide } from "./videos/social/promo/Wide";
import { HERO_S, Hero } from "./videos/archive/hero-short/Hero";
import { HeroFeed, HeroWide } from "./videos/website/Hero";

/** Frame sizes (promo/PROMO-PLAYBOOK.md §1). */
const SIZE = {
  wide: { width: 1920, height: 1080 },
  feed: { width: 1080, height: 1350 },
  tall: { width: 1080, height: 1920 },
};

/** "Clean Pulse", ElevenLabs Music, from the user (2026-10-15). */
const music = "explainer-music.mp3";

// Grouped by where the video goes. The id starts with that group (Web, Social,
// Archive) and ends with the frame (16x9, 4x5, 9x16); scripts/render.sh files
// each render under out/<group>/ by that prefix.
export const RemotionRoot: React.FC = () => (
  <>
    {/* On pushtype.app: the promo's website edition (laptops 16:9, phones 4:5). */}
    <Folder name="Website">
      <Composition id="WebHero16x9" component={HeroWide} durationInFrames={s(50)} fps={FPS} {...SIZE.wide} />
      <Composition id="WebHero4x5" component={HeroFeed} durationInFrames={s(28.5)} fps={FPS} {...SIZE.feed} />
    </Folder>

    {/* Ads and posts: 16:9 YouTube, 4:5 Instagram/Facebook feed, 9:16 Reels/Stories/TikTok. */}
    <Folder name="Social">
      <Composition id="SocialPromo16x9" component={Wide} durationInFrames={s(50)} fps={FPS} {...SIZE.wide} />
      <Composition id="SocialPromo4x5" component={Feed} durationInFrames={s(28.5)} fps={FPS} {...SIZE.feed} />
      <Composition id="SocialPromo9x16" component={Tall} durationInFrames={s(28.5)} fps={FPS} {...SIZE.tall} />
    </Folder>

    {/* Not in use; kept so they can be re-rendered. */}
    <Folder name="Archive">
      <Composition id="ArchiveHeroShort16x9" component={Hero} durationInFrames={s(HERO_S)} fps={FPS} {...SIZE.wide} defaultProps={{ format: "wide" as const }} />
      <Composition id="ArchiveHeroShort4x5" component={Hero} durationInFrames={s(HERO_S)} fps={FPS} {...SIZE.feed} defaultProps={{ format: "feed" as const }} />
      <Composition
        id="ArchiveExplainer16x9"
        component={Explainer}
        durationInFrames={s(DURATION_S)}
        fps={FPS}
        {...SIZE.wide}
        defaultProps={{ vertical: false, music }}
      />
      <Composition
        id="ArchiveExplainer9x16"
        component={Explainer}
        durationInFrames={s(DURATION_S)}
        fps={FPS}
        {...SIZE.tall}
        defaultProps={{ vertical: true, music }}
      />
    </Folder>
  </>
);
