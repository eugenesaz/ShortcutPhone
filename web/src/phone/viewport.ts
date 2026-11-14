// What the phone tells the agent about its screen, so the agent can enforce capacity.
// The current orientation is measured from the DOM; the other one is remembered from an
// earlier measurement or estimated from the layout in phone.css.

import { GAP, type Viewport } from "../shared/capacity";
import type { OrientationLayout, Size } from "../shared/protocol";

export type Orientation = "portrait" | "landscape";

/** `--strip` in phone.css. */
export const STRIP = 72;
export const LAYOUTS_KEY = "shortcutphone.layouts";

/** Matches CSS `orientation`: landscape only when wider than tall. */
export function orientationOf(window: Size): Orientation {
  return window.w > window.h ? "landscape" : "portrait";
}

/** Page and strip content boxes for a window, following the grid in phone.css. */
export function estimateLayout(
  orientation: Orientation,
  window: Size,
  header: number,
): OrientationLayout {
  if (orientation === "portrait") {
    return {
      page: { w: window.w - 2 * GAP, h: window.h - header - STRIP - 3 * GAP },
      strip: { w: window.w - 2 * GAP, h: STRIP },
    };
  }
  return {
    page: { w: window.w - STRIP - 3 * GAP, h: window.h - header - 2 * GAP },
    strip: { w: STRIP - GAP, h: window.h - 2 * GAP },
  };
}

export interface Measurement {
  window: Size;
  header: number;
  layout: OrientationLayout;
}

type Remembered = Partial<Record<Orientation, OrientationLayout>>;

const clampSize = (size: Size): Size => ({
  w: Math.max(0, Math.floor(size.w)),
  h: Math.max(0, Math.floor(size.h)),
});
const clampLayout = (layout: OrientationLayout): OrientationLayout => ({
  page: clampSize(layout.page),
  strip: clampSize(layout.strip),
});

/** Remembers each orientation's last measured layout (in storage, across reloads). */
export class ViewportTracker {
  private remembered: Remembered;

  constructor(private readonly storage?: Pick<Storage, "getItem" | "setItem">) {
    this.remembered = load(storage);
  }

  /** Both orientations: this measurement, plus the other one remembered or estimated. */
  update(measurement: Measurement): Viewport {
    const current = orientationOf(measurement.window);
    const other: Orientation = current === "portrait" ? "landscape" : "portrait";
    const layout = clampLayout(measurement.layout);
    if (JSON.stringify(this.remembered[current]) !== JSON.stringify(layout)) {
      this.remembered[current] = layout;
      try {
        this.storage?.setItem(LAYOUTS_KEY, JSON.stringify(this.remembered));
      } catch {
        // Storage full or blocked: the layout is still used for this session.
      }
    }
    const swapped = { w: measurement.window.h, h: measurement.window.w };
    const otherLayout =
      this.remembered[other] ?? clampLayout(estimateLayout(other, swapped, measurement.header));
    return current === "portrait"
      ? { portrait: layout, landscape: otherLayout }
      : { portrait: otherLayout, landscape: layout };
  }
}

function isSize(value: unknown): value is Size {
  if (typeof value !== "object" || value === null) return false;
  const { w, h } = value as Record<string, unknown>;
  return typeof w === "number" && typeof h === "number" && w >= 0 && h >= 0;
}

function isLayout(value: unknown): value is OrientationLayout {
  if (typeof value !== "object" || value === null) return false;
  const { page, strip } = value as Record<string, unknown>;
  return isSize(page) && isSize(strip);
}

function load(storage?: Pick<Storage, "getItem">): Remembered {
  try {
    const parsed: unknown = JSON.parse(storage?.getItem(LAYOUTS_KEY) ?? "{}");
    if (typeof parsed !== "object" || parsed === null) return {};
    const record = parsed as Record<string, unknown>;
    const result: Remembered = {};
    if (isLayout(record.portrait)) result.portrait = record.portrait;
    if (isLayout(record.landscape)) result.landscape = record.landscape;
    return result;
  } catch {
    return {};
  }
}
