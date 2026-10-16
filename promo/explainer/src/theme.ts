import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

// The website's dark theme (website/assets/tokens.css).
export const color = {
  studio: "#141416",
  raised: "#1e1e22",
  ink: "#efede8",
  muted: "#a7a39b",
  chrome: "#3a3d44",
  walnut: "#b88a63",
  onAir: "#ff5a45",
  peach: "#ffb38a",
  coral: "#ff7a5c",
  violet: "#6b3fc4",
};

export const font = {
  display: "Archivo",
  body: "Instrument Sans",
  mono: "JetBrains Mono",
};

void Promise.all([
  loadFont({ family: font.display, url: staticFile("fonts/archivo-latin.woff2"), weight: "400 900" }),
  loadFont({ family: font.body, url: staticFile("fonts/instrument-sans-latin.woff2"), weight: "400 700" }),
  loadFont({ family: font.mono, url: staticFile("fonts/jetbrains-mono-latin.woff2"), weight: "400" }),
]);

export const FPS = 30;
export const DURATION_S = 21;
/** The voiceover starts this late, so the first frame isn't mid-word. */
export const VO_OFFSET_S = 0.4;
