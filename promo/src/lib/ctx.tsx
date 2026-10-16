import React, { createContext, useContext } from "react";
import { COPY, Copy, Lang } from "./copy";

export type Format = "wide" | "tall";

type Ctx = { lang: Lang; format: Format; copy: Copy; t: number; fps: number; W: number; H: number };

const Context = createContext<Ctx>({ lang: "en", format: "wide", copy: COPY.en, t: 0, fps: 30, W: 1920, H: 1080 });

export const Provider: React.FC<{ value: Ctx; children: React.ReactNode }> = ({ value, children }) => (
  <Context.Provider value={value}>{children}</Context.Provider>
);

/** Global time in seconds, language, format and the copy for it. */
export const useCtx = () => useContext(Context);
