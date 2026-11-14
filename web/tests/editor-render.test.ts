import { describe, expect, test } from "vitest";
import { PIXEL5 } from "../src/shared/capacity";
import { describePath, renderEditor, type EditorModel } from "../src/editor/render";
import { APPS, FakeApi, device, mount, q, specConfig, tileLabels } from "./editor-support";

describe("editor: read-only view", () => {
  test("shows the global strip, each page, icons and N / max counters", async () => {
    const { root } = await mount();
    expect(tileLabels(root, '[data-section="global"]')).toEqual(["Safari", "Slack"]);
    expect(q(root, '[data-section="global"] .counter').textContent).toBe(
      "2 apps · 6 fit without scrolling",
    );
    expect(q(root, '[data-section="global"] .tile[data-index="0"] .pin')).toBeTruthy();

    const page = q(root, '[data-section="page"][data-page="0"]');
    expect(q(page, "h3").textContent).toBe("Slack");
    expect(q(page, ".mono").textContent).toBe("com.tinyspeck.slackmacgap");
    expect(q(page, ".counter").textContent).toBe("2 / 55");
    expect(tileLabels(page, "")).toEqual(["LGTM", "Jump to"]);
    expect(q<HTMLImageElement>(page, ".page-icon").getAttribute("src")).toBe(
      "/icons/com.tinyspeck.slackmacgap.png?size=64",
    );
    const safari = q(root, '[data-section="global"] .tile[data-index="0"] img');
    expect(safari.getAttribute("src")).toBe("/icons/com.apple.Safari.png?size=64");
    expect(q(page, '.tile[data-index="0"] .emoji').textContent).toBe("👍");
  });

  test("custom colors reach the tile", async () => {
    const { root } = await mount();
    const slack = q(root, '[data-section="global"] .tile[data-index="1"]');
    expect(slack.style.getPropertyValue("--tile-color")).toBe("#4A154B");
  });

  test("counters use the smallest reported phone", async () => {
    const small = {
      portrait: { page: { w: 248, h: 248 }, strip: { w: 248, h: 72 } },
      landscape: { page: { w: 248, h: 248 }, strip: { w: 72, h: 248 } },
    };
    const { root } = await mount(
      new FakeApi(specConfig(), [device("a", PIXEL5), device("b", small)]),
    );
    expect(q(root, '[data-section="page"] .counter').textContent).toBe("2 / 16");
    expect(q(root, '[data-section="global"] .counter').textContent).toBe(
      "2 apps · 4 fit without scrolling",
    );
  });

  test("all saved, nothing to save", async () => {
    const { root } = await mount();
    expect(q(root, ".status").textContent).toBe("All changes saved");
    expect(q<HTMLButtonElement>(root, '[data-action="save"]').disabled).toBe(true);
  });

  test("shows a banner when config.json on disk is invalid", async () => {
    const api = new FakeApi();
    api.diskIssues = [{ path: "", message: "invalid JSON" }];
    const { root } = await mount(api);
    expect(q(root, ".banner--error").textContent).toContain("config.json on disk is invalid");
  });

  test("shows an error when the agent can't be reached", async () => {
    const api = new FakeApi();
    api.config = () => Promise.reject(new Error("HTTP 403"));
    const { root } = await mount(api);
    expect(q(root, ".banner--error").textContent).toContain("HTTP 403");
    expect(root.querySelector('[data-section="global"]')).toBeNull();
  });

  test("labels go through textContent", async () => {
    const config = specConfig();
    const first = config.pages[0]?.buttons[0];
    if (first) first.label = "<img src=x onerror=alert(1)>";
    const { root } = await mount(new FakeApi(config));
    expect(root.querySelector('img[src="x"]')).toBeNull();
    expect(tileLabels(root, '[data-section="page"]')[0]).toBe("<img src=x onerror=alert(1)>");
  });

  test("describePath names the page app and button", () => {
    const model = {
      config: specConfig(),
      apps: APPS,
    } as unknown as EditorModel;
    expect(describePath(model, "pages[0].buttons[1].keys")).toBe("Slack › button 2 › keys");
    expect(describePath(model, "global[0].bundleId")).toBe("Global strip › button 1 › bundleId");
    expect(describePath(model, "global")).toBe("Global strip");
    expect(describePath(model, "pages[0].columns")).toBe("Slack › columns");
  });

  test("renderEditor works without a controller", () => {
    document.body.innerHTML = '<div id="app"></div>';
    const root = q(document, "#app");
    const config = specConfig();
    renderEditor(root, {
      config,
      saved: config,
      apps: APPS,
      devices: [],
      diskErrors: [],
      serverIssues: [],
      selection: null,
      blocked: {},
      newPageApp: "",
      saving: false,
      notice: null,
    });
    expect(root.querySelectorAll('[data-section="page"]').length).toBe(1);
  });
});
