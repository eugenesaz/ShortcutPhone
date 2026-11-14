// Config types (schema version 1). Mirrors Sources/ShortcutPhoneCore/{Config,Page,Button}.swift.

import { isArrayOf, isNumber, isOptionalString, isRecord, isString } from "./guards";

interface ButtonFace {
  id: string;
  label?: string;
  emoji?: string;
  /** `#RRGGBB` */
  color?: string;
  /** Global strip only: shown before the unpinned apps. */
  pinned?: boolean;
}

export interface AppButton extends ButtonFace {
  type: "app";
  bundleId: string;
}

export interface TextButton extends ButtonFace {
  type: "text";
  text: string;
}

export interface KeysButton extends ButtonFace {
  type: "keys";
  keys: string;
}

/** Opens `url` in the page's app (a browser). Page buttons only. */
export interface UrlButton extends ButtonFace {
  type: "url";
  url: string;
}

/** What the phone does after a button in a folder is tapped. */
export type AfterPress = "back" | "stay";

/**
 * A group of buttons the phone opens in place of the page grid. Page buttons only, never
 * nested. The phone opens it itself; nothing is sent to the Mac.
 */
export interface FolderButton extends ButtonFace {
  type: "folder";
  afterPress: AfterPress;
  /** Fixed column count 1–8, or `null` to let the phone pick. */
  columns: number | null;
  buttons: Button[];
}

export type Button = AppButton | TextButton | KeysButton | UrlButton | FolderButton;

/** Every button kind a folder can hold. */
export type LeafButton = Exclude<Button, FolderButton>;

/** The site's host name without `www.`, used when a `url` button has no label. */
export function urlHost(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return url;
  }
}

export interface Page {
  bundleId: string;
  /** Fixed column count 1–8, or `null` to let the phone pick. */
  columns: number | null;
  buttons: Button[];
}

export interface Config {
  version: 1;
  server: { port: number };
  global: Button[];
  pages: Page[];
}

export function isButton(value: unknown): value is Button {
  if (!isRecord(value) || !isString(value.id)) return false;
  if (!isOptionalString(value.label) || !isOptionalString(value.emoji)) return false;
  if (!isOptionalString(value.color)) return false;
  if (value.pinned !== undefined && typeof value.pinned !== "boolean") return false;
  switch (value.type) {
    case "app":
      return isString(value.bundleId);
    case "text":
      return isString(value.text);
    case "keys":
      return isString(value.keys);
    case "url":
      return isString(value.url);
    case "folder":
      return (
        (value.afterPress === "back" || value.afterPress === "stay") &&
        (value.columns === null || isNumber(value.columns)) &&
        isArrayOf(value.buttons, isButton)
      );
    default:
      return false;
  }
}

export function isPage(value: unknown): value is Page {
  return (
    isRecord(value) &&
    isString(value.bundleId) &&
    (value.columns === null || isNumber(value.columns)) &&
    isArrayOf(value.buttons, isButton)
  );
}

export function isConfig(value: unknown): value is Config {
  return (
    isRecord(value) &&
    value.version === 1 &&
    isRecord(value.server) &&
    isNumber(value.server.port) &&
    isArrayOf(value.global, isButton) &&
    isArrayOf(value.pages, isPage)
  );
}

/** Every button in `buttons`, including those inside folders. */
export function allButtons(buttons: readonly Button[]): Button[] {
  return buttons.flatMap((b) => (b.type === "folder" ? [b, ...b.buttons] : [b]));
}
