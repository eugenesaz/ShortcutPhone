import { describe, expect, test } from "vitest";
import { effectiveCapacity } from "../src/shared/capacity";
import type { Config } from "../src/shared/config";
import { allIssues, configIssues, isBundleId } from "../src/editor/validate";
import { setColumns, newButtonId, sameConfig, withType } from "../src/editor/state";
import { specConfig } from "./editor-support";

const paths = (config: Config): string[] => configIssues(config).map((i) => i.path);

describe("editor validation mirrors ConfigValidator.swift", () => {
  test("the spec example is valid", () => {
    expect(allIssues(specConfig(), effectiveCapacity([]))).toEqual([]);
  });

  test("duplicate ids, bad color, empty text, non-app global", () => {
    const config = specConfig();
    config.global.push({ id: "btn_1", type: "text", label: "x", text: "" });
    const first = config.pages[0]?.buttons[0];
    if (first) first.color = "red";
    expect(paths(config)).toEqual([
      "global[2].id",
      "global[2].type",
      "global[2].text",
      "pages[0].buttons[0].color",
    ]);
  });

  test("duplicate pages and bad bundle ids", () => {
    const config = specConfig();
    config.pages.push({ bundleId: "com.tinyspeck.slackmacgap", columns: 9, buttons: [] });
    config.pages.push({ bundleId: "nodot", columns: null, buttons: [] });
    expect(paths(config)).toEqual(["pages[1].bundleId", "pages[1].columns", "pages[2].bundleId"]);
  });

  test("web-page buttons: http(s) only, page only, no label needed", () => {
    const config = specConfig();
    config.pages[0]?.buttons.push(
      { id: "u1", type: "url", url: "https://example.com" },
      { id: "u2", type: "url", url: "javascript:alert(1)" },
      { id: "u3", type: "url", url: "example.com" },
    );
    config.global.push({ id: "u4", type: "url", url: "https://example.com" });
    expect(paths(config)).toEqual([
      "global[2].type",
      "pages[0].buttons[3].url",
      "pages[0].buttons[4].url",
    ]);
  });

  test("bundle ids", () => {
    expect(isBundleId("com.apple.Safari")).toBe(true);
    expect(isBundleId("com.example.my-app_2")).toBe(true);
    for (const bad of ["", "nodot", ".com.x", "com.x.", "com.x y", "com.é.x"]) {
      expect(isBundleId(bad)).toBe(false);
    }
  });
});

describe("editor state helpers", () => {
  test("setColumns accepts a fitting value", () => {
    const result = setColumns(specConfig(), 0, 4, effectiveCapacity([]));
    expect("config" in result && result.config.pages[0]?.columns).toBe(4);
  });

  test("new ids are unique", () => {
    const config = specConfig();
    let calls = 0;
    // The first draw collides with nothing; force a collision by returning btn_00000001 twice.
    config.global.push({ id: "btn_00000001", type: "app", bundleId: "com.apple.Notes" });
    const id = newButtonId(config, () => (calls++ === 0 ? 1 / 0x100000000 : 2 / 0x100000000));
    expect(id).toBe("btn_00000002");
  });

  test("changing type keeps the face", () => {
    const changed = withType(
      { id: "a", type: "text", label: "L", emoji: "😀", text: "t" },
      "keys",
      "com.apple.Notes",
    );
    expect(changed).toEqual({ id: "a", type: "keys", label: "L", emoji: "😀", keys: "" });
  });

  test("sameConfig ignores key order but not values", () => {
    const a: Config = {
      version: 1,
      server: { port: 1 },
      global: [{ id: "x", type: "app", bundleId: "a.b" }],
      pages: [],
    };
    const reordered = JSON.parse(
      '{"pages":[],"global":[{"bundleId":"a.b","type":"app","id":"x"}],"server":{"port":1},"version":1}',
    ) as Config;
    expect(sameConfig(a, reordered)).toBe(true);
    expect(sameConfig(a, { ...a, server: { port: 2 } })).toBe(false);
  });
});
