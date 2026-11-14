// Pure edit operations on a config draft. Each returns a new config and never mutates its
// input. Capacity guards live here too, so the UI and the tests share them.

import { MIN_TILE, type EffectiveCapacity } from "../shared/capacity";
import type { Button, Config } from "../shared/config";

/** Where a button lives: the global strip, or page `page`. */
export type Scope = { kind: "global" } | { kind: "page"; page: number };

export interface ButtonRef {
  scope: Scope;
  index: number;
}

export type ButtonType = Button["type"];

const clone = (config: Config): Config => JSON.parse(JSON.stringify(config)) as Config;

export function buttonsIn(config: Config, scope: Scope): Button[] {
  return scope.kind === "global" ? config.global : (config.pages[scope.page]?.buttons ?? []);
}

export function getButton(config: Config, ref: ButtonRef): Button | undefined {
  return buttonsIn(config, ref.scope)[ref.index];
}

/** Field path prefix used by validation, e.g. `pages[2].buttons[0]`. */
export function buttonPath(ref: ButtonRef): string {
  return ref.scope.kind === "global"
    ? `global[${String(ref.index)}]`
    : `pages[${String(ref.scope.page)}].buttons[${String(ref.index)}]`;
}

export function scopePath(scope: Scope): string {
  return scope.kind === "global" ? "global" : `pages[${String(scope.page)}].buttons`;
}

/** `btn_` + 8 random hex digits, unique within `config`. */
export function newButtonId(config: Config, random: () => number = Math.random): string {
  const taken = new Set(
    [...config.global, ...config.pages.flatMap((p) => p.buttons)].map((b) => b.id),
  );
  for (;;) {
    const hex = Math.floor(random() * 0x100000000)
      .toString(16)
      .padStart(8, "0");
    const id = `btn_${hex}`;
    if (!taken.has(id)) return id;
  }
}

/** Max buttons on page `page`, or `null` when its `columns` override doesn't fit. */
export function pageCapacityOf(
  config: Config,
  page: number,
  capacity: EffectiveCapacity,
): number | null {
  return capacity.page(config.pages[page]?.columns ?? null);
}

/** The global strip scrolls, so it never fills up; pages do. */
export function canAdd(config: Config, scope: Scope, capacity: EffectiveCapacity): boolean {
  if (scope.kind === "global") return true;
  const max = pageCapacityOf(config, scope.page, capacity);
  return max !== null && buttonsIn(config, scope).length < max;
}

export function addButton(
  config: Config,
  scope: Scope,
  button: Button,
): { config: Config; ref: ButtonRef } {
  const next = clone(config);
  const list = buttonsIn(next, scope);
  list.push(button);
  return { config: next, ref: { scope, index: list.length - 1 } };
}

export function updateButton(
  config: Config,
  ref: ButtonRef,
  change: (button: Button) => Button,
): Config {
  const next = clone(config);
  const list = buttonsIn(next, ref.scope);
  const button = list[ref.index];
  if (button) list[ref.index] = change(button);
  return next;
}

export function removeButton(config: Config, ref: ButtonRef): Config {
  const next = clone(config);
  buttonsIn(next, ref.scope).splice(ref.index, 1);
  return next;
}

/**
 * Whether a button can move by `delta`. In the global strip, pinned and unpinned apps stay in
 * their own groups, so the editor order matches what the phone shows.
 */
export function canMove(config: Config, ref: ButtonRef, delta: number): boolean {
  const list = buttonsIn(config, ref.scope);
  const to = ref.index + delta;
  const moving = list[ref.index];
  const other = list[to];
  if (!moving || !other) return false;
  return ref.scope.kind !== "global" || Boolean(moving.pinned) === Boolean(other.pinned);
}

/** Moves a button by `delta` places within its scope; returns its new index. */
export function moveButton(
  config: Config,
  ref: ButtonRef,
  delta: number,
): { config: Config; ref: ButtonRef } {
  if (!canMove(config, ref, delta)) return { config, ref };
  const next = clone(config);
  const list = buttonsIn(next, ref.scope);
  const to = ref.index + delta;
  const [button] = list.splice(ref.index, 1);
  if (button) list.splice(to, 0, button);
  return { config: next, ref: { scope: ref.scope, index: to } };
}

/** Switches the action type, keeping id, label, emoji and color. */
export function withType(button: Button, type: ButtonType, defaultBundleId: string): Button {
  if (button.type === type) return button;
  const { id, label, emoji, color } = button;
  const face: Pick<Button, "id"> & Partial<Pick<Button, "label" | "emoji" | "color">> = { id };
  if (label !== undefined) face.label = label;
  if (emoji !== undefined) face.emoji = emoji;
  if (color !== undefined) face.color = color;
  switch (type) {
    case "app":
      return { ...face, type, bundleId: defaultBundleId };
    case "text":
      return { ...face, type, text: "" };
    case "keys":
      return { ...face, type, keys: "" };
    case "url":
      return { ...face, type, url: "https://" };
  }
}

/** Sets an optional face field; an empty value removes it. */
export function withFace(
  button: Button,
  field: "label" | "emoji" | "color",
  value: string | undefined,
): Button {
  const next = { ...button };
  const set = value !== undefined && value !== "";
  switch (field) {
    case "label":
      if (set) next.label = value;
      else delete next.label;
      break;
    case "emoji":
      if (set) next.emoji = value;
      else delete next.emoji;
      break;
    case "color":
      if (set) next.color = value;
      else delete next.color;
      break;
  }
  return next;
}

/**
 * Pins or unpins global button `index`. Pinning moves it to the end of the pinned group;
 * unpinning moves it to the start of the unpinned ones. Returns its new place.
 */
export function setPinned(
  config: Config,
  index: number,
  pinned: boolean,
): { config: Config; ref: ButtonRef } {
  const next = clone(config);
  const [button] = next.global.splice(index, 1);
  if (!button) return { config, ref: { scope: { kind: "global" }, index } };
  if (pinned) button.pinned = true;
  else delete button.pinned;
  const firstUnpinned = next.global.findIndex((b) => !b.pinned);
  const to = firstUnpinned === -1 ? next.global.length : firstUnpinned;
  next.global.splice(to, 0, button);
  return { config: next, ref: { scope: { kind: "global" }, index: to } };
}

export function addPage(config: Config, bundleId: string): Config {
  const next = clone(config);
  next.pages.push({ bundleId, columns: null, buttons: [] });
  return next;
}

export function removePage(config: Config, page: number): Config {
  const next = clone(config);
  next.pages.splice(page, 1);
  return next;
}

export function movePage(config: Config, page: number, delta: number): Config {
  const to = page + delta;
  if (to < 0 || to >= config.pages.length) return config;
  const next = clone(config);
  const [moved] = next.pages.splice(page, 1);
  if (moved) next.pages.splice(to, 0, moved);
  return next;
}

/**
 * Changes a page's `columns`. Refused, with the reason, if the override makes tiles too small
 * or leaves fewer places than the page has buttons.
 */
export function setColumns(
  config: Config,
  page: number,
  columns: number | null,
  capacity: EffectiveCapacity,
): { config: Config } | { error: string } {
  const current = config.pages[page];
  if (!current) return { config };
  const max = capacity.page(columns);
  const what = columns === null ? "Auto columns" : `${String(columns)} columns`;
  if (max === null) {
    return {
      error: `${what} make tiles smaller than ${String(MIN_TILE)} px on a paired phone.`,
    };
  }
  if (current.buttons.length > max) {
    return {
      error: `${what} hold only ${String(max)} buttons; this page has ${String(current.buttons.length)}. Remove buttons first.`,
    };
  }
  const next = clone(config);
  const target = next.pages[page];
  if (target) target.columns = columns;
  return { config: next };
}

/** JSON with sorted keys, so key order doesn't count as a change. */
function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v: unknown) =>
    v !== null && typeof v === "object" && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => (a < b ? -1 : 1)))
      : v,
  );
}

/** Whether the two configs would save the same JSON. */
export function sameConfig(a: Config, b: Config): boolean {
  return canonical(a) === canonical(b);
}
