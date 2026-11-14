// WebSocket messages. Mirrors Sources/ShortcutPhoneCore/Protocol.swift; both sides are
// checked against Tests/Fixtures/protocol.

import { isButton, isPage, type Button, type Page } from "./config";
import { isArrayOf, isRecord, isString } from "./guards";

export interface AppRef {
  bundleId: string;
  name: string;
}

/** CSS pixels. */
export interface Size {
  w: number;
  h: number;
}

export interface OrientationLayout {
  page: Size;
  strip: Size;
}

export type PressError = "wrong_app" | "no_accessibility" | "launch_failed" | "unknown_button";

const PRESS_ERRORS: readonly string[] = [
  "wrong_app",
  "no_accessibility",
  "launch_failed",
  "unknown_button",
] satisfies PressError[];

export interface StateMsg {
  type: "state";
  frontmost: AppRef | null;
  global: Button[];
  page: Page | null;
}

export type ResultMsg =
  | { type: "result"; pressId: string; ok: true }
  | { type: "result"; pressId: string; ok: false; error: PressError };

/** Agent → phone. */
export type ServerMsg = StateMsg | ResultMsg;

/** Phone → agent. */
export type ClientMsg =
  | { type: "auth"; token: string }
  | { type: "press"; pressId: string; buttonId: string }
  | { type: "viewport"; portrait: OrientationLayout; landscape: OrientationLayout };

function isAppRef(value: unknown): value is AppRef {
  return isRecord(value) && isString(value.bundleId) && isString(value.name);
}

function isPressError(value: unknown): value is PressError {
  return isString(value) && PRESS_ERRORS.includes(value);
}

export function isServerMsg(value: unknown): value is ServerMsg {
  if (!isRecord(value)) return false;
  switch (value.type) {
    case "state":
      return (
        (value.frontmost === null || isAppRef(value.frontmost)) &&
        isArrayOf(value.global, isButton) &&
        (value.page === null || isPage(value.page))
      );
    case "result":
      if (!isString(value.pressId)) return false;
      if (value.ok === true) return true;
      return value.ok === false && isPressError(value.error);
    default:
      return false;
  }
}

/** Parses one WebSocket frame. Returns `null` for anything malformed: never trust the wire. */
export function parseServerMsg(raw: string): ServerMsg | null {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return null;
  }
  return isServerMsg(value) ? value : null;
}

export function authMsg(token: string): ClientMsg {
  return { type: "auth", token };
}

export function pressMsg(pressId: string, buttonId: string): ClientMsg {
  return { type: "press", pressId, buttonId };
}

export function viewportMsg(portrait: OrientationLayout, landscape: OrientationLayout): ClientMsg {
  return { type: "viewport", portrait, landscape };
}
