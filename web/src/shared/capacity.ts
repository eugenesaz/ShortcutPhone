// How many buttons fit on a phone without scrolling. Mirrors
// Sources/ShortcutPhoneCore/Capacity.swift; both are checked against Tests/Fixtures/capacity.json.

import type { OrientationLayout, Size } from "./protocol";

/** Smallest tile edge, CSS px. */
export const MIN_TILE = 56;
/** Gap between tiles, CSS px. */
export const GAP = 8;

export interface Viewport {
  portrait: OrientationLayout;
  landscape: OrientationLayout;
}

/** Used until a phone reports its own size: Pixel 5, 393×851 CSS px. */
export const PIXEL5: Viewport = {
  portrait: { page: { w: 393, h: 700 }, strip: { w: 393, h: 72 } },
  landscape: { page: { w: 700, h: 345 }, strip: { w: 72, h: 393 } },
};

/** Minimum-size tiles that fit along one edge. */
export function tilesAlong(length: number): number {
  return Math.max(0, Math.floor((length + GAP) / (MIN_TILE + GAP)));
}

/** Whether `columns` tiles of at least MIN_TILE fit side by side in `width`. */
export function columnsFit(columns: number, width: number): boolean {
  return columns >= 1 && (width - GAP * (columns - 1)) / columns >= MIN_TILE;
}

/** Page capacity of one page area, or `null` if the `columns` override doesn't fit. */
export function pageCapacity(size: Size, columns: number | null): number | null {
  const rows = tilesAlong(size.h);
  if (columns === null) return tilesAlong(size.w) * rows;
  return columnsFit(columns, size.w) ? columns * rows : null;
}

/** Global-strip capacity of one device: one row in portrait, one column in landscape. */
export function stripCapacity(viewport: Viewport): number {
  const row = viewport.portrait.strip;
  const column = viewport.landscape.strip;
  const inRow = tilesAlong(row.h) > 0 ? tilesAlong(row.w) : 0;
  const inColumn = tilesAlong(column.w) > 0 ? tilesAlong(column.h) : 0;
  return Math.min(inRow, inColumn);
}

export interface EffectiveCapacity {
  /** Max buttons on a page with this `columns` override; `null` if the override doesn't fit. */
  page(columns: number | null): number | null;
  /** Max buttons in the global strip. */
  strip: number;
}

/** The smallest capacity across all devices and both orientations; Pixel 5 if none reported. */
export function effectiveCapacity(viewports: readonly Viewport[]): EffectiveCapacity {
  const used = viewports.length > 0 ? viewports : [PIXEL5];
  return {
    page(columns) {
      let result = Infinity;
      for (const vp of used) {
        for (const layout of [vp.portrait, vp.landscape]) {
          const value = pageCapacity(layout.page, columns);
          if (value === null) return null;
          result = Math.min(result, value);
        }
      }
      return result;
    },
    strip: Math.min(...used.map(stripCapacity)),
  };
}
