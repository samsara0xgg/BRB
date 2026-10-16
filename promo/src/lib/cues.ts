import cues from "../cues.json";

/** The master timeline, in seconds. scripts/soundtrack.py reads the same file. */
export const Q = cues;
export type Cues = typeof cues;
