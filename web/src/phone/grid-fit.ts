// Picks the page grid: the largest square-ish tiles that fit every button without scrolling.

import { GAP, MIN_TILE, columnsFit, tilesAlong } from "../shared/capacity";
import type { Size } from "../shared/protocol";

export interface GridFit {
  cols: number;
  rows: number;
  /** Largest square tile edge in this grid, CSS px. */
  tile: number;
  /**
   * Buttons that don't fit. When > 0 the grid is at minimum size and its last cell is the
   * "+N hidden" tile, so `cols × rows − 1` buttons are shown.
   */
  overflow: number;
}

function tileSize(size: Size, cols: number, rows: number): number {
  return Math.min((size.w - GAP * (cols - 1)) / cols, (size.h - GAP * (rows - 1)) / rows);
}

/** An invalid `columns` override (tiles under MIN_TILE) is ignored. */
export function gridFit(count: number, size: Size, columns: number | null = null): GridFit {
  const override = columns !== null && columnsFit(columns, size.w) ? columns : null;
  if (count <= 0) return { cols: 0, rows: 0, tile: 0, overflow: 0 };

  let best: GridFit | null = null;
  const candidates =
    override !== null ? [override] : Array.from({ length: count }, (_, i) => i + 1);
  for (const cols of candidates) {
    const rows = Math.ceil(count / cols);
    const tile = tileSize(size, cols, rows);
    if (best === null || tile > best.tile) best = { cols, rows, tile, overflow: 0 };
  }
  if (best !== null && best.tile >= MIN_TILE) return best;

  // Doesn't fit: fill the grid at minimum size; the last cell becomes the overflow tile.
  const cols = override ?? tilesAlong(size.w);
  const rows = tilesAlong(size.h);
  const slots = cols * rows;
  if (slots === 0) return { cols: 0, rows: 0, tile: 0, overflow: count };
  return {
    cols,
    rows,
    tile: tileSize(size, cols, rows),
    overflow: count > slots ? count - (slots - 1) : 0,
  };
}
