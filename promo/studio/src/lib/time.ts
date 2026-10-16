/** Every composition runs at 30 fps (the recordings are 30 fps). */
export const FPS = 30;

/** Seconds of the finished video to frames. Write every time in seconds and wrap it in s(). */
export const s = (seconds: number) => Math.round(seconds * FPS);
