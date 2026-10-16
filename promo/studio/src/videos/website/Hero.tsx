import React from "react";
import { Feed } from "../social/promo/Feed";
import { Wide } from "../social/promo/Wide";

/**
 * The website hero is the promo itself (the user likes it as it is), in its
 * website edition: the same cut with labels and small print raised to a
 * readable size and the hook captioned, because the site plays it muted at
 * about a quarter of its size (≈500 px wide on a laptop, 330–480 px on phones).
 */
export const HeroWide: React.FC = () => <Wide web />;
export const HeroFeed: React.FC = () => <Feed web />;
