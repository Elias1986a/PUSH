/**
 * Applies to the CLI and Studio only; the Node APIs take these as options.
 * All options: https://remotion.dev/docs/config
 */

import { Config } from "@remotion/cli/config";

Config.setRspack(true);
// PNG frames keep text edges clean (JPEG smears them).
Config.setVideoImageFormat("png");
Config.setOverwriteOutput(true);
Config.setDefaultPremountInSeconds(2);
// Tag output bt709 / yuv420p; the default tag made many players lift the blacks.
Config.setColorSpace("bt709");
