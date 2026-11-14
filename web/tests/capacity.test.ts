import { describe, expect, test } from "vitest";
import { PIXEL5, effectiveCapacity, type Viewport } from "../src/shared/capacity";
import { gridFit, type GridFit } from "../src/phone/grid-fit";
import type { Size } from "../src/shared/protocol";
import { fixtureJson } from "./fixtures";

interface CapacityCase {
  name: string;
  viewports: Viewport[];
  columns: number | null;
  expect: { page: number | null; strip: number };
}

interface GridCase {
  name: string;
  count: number;
  page: Size;
  columns: number | null;
  expect: GridFit;
}

const fixtures = fixtureJson("capacity.json") as {
  pixel5: Viewport;
  capacity: CapacityCase[];
  gridFit: GridCase[];
};

describe("capacity", () => {
  test("Pixel 5 profile matches the shared fixture", () => {
    expect(PIXEL5).toEqual(fixtures.pixel5);
  });

  test.each(fixtures.capacity)("$name", ({ viewports, columns, expect: want }) => {
    const capacity = effectiveCapacity(viewports);
    expect(capacity.page(columns)).toBe(want.page);
    expect(capacity.strip).toBe(want.strip);
  });
});

describe("grid fit", () => {
  test.each(fixtures.gridFit)("$name", ({ count, page, columns, expect: want }) => {
    const fit = gridFit(count, page, columns);
    expect({ ...fit, tile: 0 }).toEqual({ ...want, tile: 0 });
    expect(fit.tile).toBeCloseTo(want.tile, 2);
  });

  test("tiles never shrink below 56 px for counts up to capacity", () => {
    for (const layout of [PIXEL5.portrait, PIXEL5.landscape]) {
      const max = effectiveCapacity([PIXEL5]).page(null) ?? 0;
      for (let n = 1; n <= max; n++) {
        const fit = gridFit(n, layout.page);
        expect(fit.overflow).toBe(0);
        expect(fit.tile).toBeGreaterThanOrEqual(56);
        expect(fit.cols * fit.rows).toBeGreaterThanOrEqual(n);
      }
    }
  });
});
