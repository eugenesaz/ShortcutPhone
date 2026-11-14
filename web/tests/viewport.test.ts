import { describe, expect, test } from "vitest";
import { LAYOUTS_KEY, ViewportTracker, estimateLayout, orientationOf } from "../src/phone/viewport";

class MemoryStorage {
  items = new Map<string, string>();
  getItem(key: string): string | null {
    return this.items.get(key) ?? null;
  }
  setItem(key: string, value: string): void {
    this.items.set(key, value);
  }
}

const portraitWindow = { w: 393, h: 760 };
const measuredPortrait = { page: { w: 377, h: 640.5 }, strip: { w: 377, h: 72 } };

describe("viewport", () => {
  test("orientation follows CSS: landscape only when wider than tall", () => {
    expect(orientationOf({ w: 393, h: 760 })).toBe("portrait");
    expect(orientationOf({ w: 500, h: 500 })).toBe("portrait");
    expect(orientationOf({ w: 760, h: 393 })).toBe("landscape");
  });

  test("estimates follow the phone.css grid", () => {
    expect(estimateLayout("portrait", { w: 393, h: 760 }, 26)).toEqual({
      page: { w: 377, h: 638 },
      strip: { w: 377, h: 72 },
    });
    expect(estimateLayout("landscape", { w: 760, h: 393 }, 26)).toEqual({
      page: { w: 664, h: 351 },
      strip: { w: 64, h: 377 },
    });
  });

  test("current orientation is measured, the other estimated", () => {
    const tracker = new ViewportTracker();
    const viewport = tracker.update({
      window: portraitWindow,
      header: 26,
      layout: measuredPortrait,
    });
    expect(viewport.portrait).toEqual({ page: { w: 377, h: 640 }, strip: { w: 377, h: 72 } });
    expect(viewport.landscape).toEqual({ page: { w: 664, h: 351 }, strip: { w: 64, h: 377 } });
  });

  test("after rotating, the earlier measurement replaces the estimate", () => {
    const storage = new MemoryStorage();
    const tracker = new ViewportTracker(storage);
    tracker.update({ window: portraitWindow, header: 26, layout: measuredPortrait });
    const landscape = { page: { w: 660, h: 300 }, strip: { w: 64, h: 340 } };
    const viewport = tracker.update({ window: { w: 760, h: 356 }, header: 26, layout: landscape });
    expect(viewport.landscape).toEqual(landscape);
    expect(viewport.portrait.page).toEqual({ w: 377, h: 640 });
  });

  test("measurements survive a reload via storage", () => {
    const storage = new MemoryStorage();
    const landscape = { page: { w: 660, h: 300 }, strip: { w: 64, h: 340 } };
    new ViewportTracker(storage).update({
      window: { w: 760, h: 356 },
      header: 26,
      layout: landscape,
    });
    const viewport = new ViewportTracker(storage).update({
      window: portraitWindow,
      header: 26,
      layout: measuredPortrait,
    });
    expect(viewport.landscape).toEqual(landscape);
  });

  test("ignores corrupt storage", () => {
    const storage = new MemoryStorage();
    storage.setItem(LAYOUTS_KEY, '{"landscape":{"page":{"w":"x"}}}');
    const viewport = new ViewportTracker(storage).update({
      window: portraitWindow,
      header: 26,
      layout: measuredPortrait,
    });
    expect(viewport.landscape.page).toEqual({ w: 664, h: 351 });
  });

  test("negative sizes are clamped to zero", () => {
    const viewport = new ViewportTracker().update({
      window: { w: 100, h: 80 },
      header: 26,
      layout: { page: { w: -3, h: 10 }, strip: { w: 10, h: 72 } },
    });
    expect(viewport.landscape.page.w).toBe(0);
  });
});
