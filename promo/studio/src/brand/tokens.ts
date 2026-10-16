import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

// The PUSHTYPE promo look (2026-10-15): near-black studio, brighter outlines and
// secondary text so dark UI keeps its edges. Accents match the website
// (website/assets/tokens.css). Rules for using them: promo/PROMO-PLAYBOOK.md.
export const color = {
  studio: "#08080a",
  raised: "#18181c",
  ink: "#efede8",
  muted: "#bdb9b1",
  chrome: "#4a4e57",
  walnut: "#b88a63",
  onAir: "#ff5a45",
  peach: "#ffb38a",
  coral: "#ff7a5c",
  violet: "#6b3fc4",
  // Measured from the Notes recordings (footage/type-small.mp4).
  noteBg: "#1a1a1a",
  noteText: "#d7d7d7",
  noteGhost: "#8e8d94",
  caret: "#e9a21c",
};

export const font = {
  /** Headlines: weight 800, fontStretch 112%, letterSpacing -0.02em. */
  display: "Archivo",
  body: "Instrument Sans",
  /** Keys and the URL. */
  mono: "JetBrains Mono",
  /** Stand-in for the Mac system font, for text drawn into a recorded note. */
  notes: "Inter",
};

// Importing this file starts the loads; loadFont holds rendering until they land.
void Promise.all([
  loadFont({ family: font.display, url: staticFile("fonts/archivo-latin.woff2"), weight: "400 900" }),
  loadFont({ family: font.body, url: staticFile("fonts/instrument-sans-latin.woff2"), weight: "400 700" }),
  loadFont({ family: font.mono, url: staticFile("fonts/jetbrains-mono-latin.woff2"), weight: "400" }),
  loadFont({ family: font.notes, url: staticFile("fonts/inter-400.woff2"), weight: "400" }),
]);
