import React from "react";
import { Audio, Sequence, interpolate, staticFile } from "remotion";
import { clamp } from "../lib/anim";
import { s } from "../lib/time";

/**
 * One bar of the music bed ("Clean Pulse", ~105 bpm), measured from the audio:
 * 4 beats × 0.5719 s. Lengthen a cut by whole bars so the bed stays on the beat.
 */
export const BAR = 2.2875;

const XF = 3; // crossfade frames at the repeat

/**
 * A music bed. With `repeatAt` (seconds of the video) and `repeat` (seconds,
 * whole bars), the stretch from `repeatAt` plays twice, so the cut can be
 * `repeat` longer and the bed still ends on its own last chord.
 * `volume` takes frames of the video. `from` is where in the file to start.
 */
export const Bed: React.FC<{
  src: string;
  volume: (frame: number) => number;
  from?: number;
  repeatAt?: number;
  repeat?: number;
}> = ({ src, volume, from = 0, repeatAt, repeat }) => {
  if (repeatAt === undefined || !repeat) {
    return <Audio src={staticFile(src)} startFrom={s(from)} volume={volume} />;
  }
  const cut = s(repeatAt + repeat);
  return (
    <>
      <Sequence durationInFrames={cut}>
        <Audio src={staticFile(src)} startFrom={s(from)} volume={(f) => volume(f) * interpolate(f, [cut - XF, cut], [1, 0], clamp)} />
      </Sequence>
      <Sequence from={cut - XF}>
        <Audio
          src={staticFile(src)}
          startFrom={s(from + repeatAt) - XF}
          volume={(f) => volume(f + cut - XF) * interpolate(f, [0, XF], [0, 1], clamp)}
        />
      </Sequence>
    </>
  );
};
