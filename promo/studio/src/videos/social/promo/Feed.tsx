import React from "react";
import { AbsoluteFill } from "remotion";
import { Tall } from "./Tall";
import type { PromoProps } from "./Wide";

/** 4:5 feed cut: not its own edit, the centre 1080×1350 of the 4:5-safe vertical layout. */
export const Feed: React.FC<PromoProps> = ({ web = false }) => (
  <AbsoluteFill style={{ overflow: "hidden" }}>
    <div style={{ position: "absolute", left: 0, top: -285, width: 1080, height: 1920 }}>
      <Tall web={web} />
    </div>
  </AbsoluteFill>
);
