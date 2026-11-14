import { beforeEach, describe, expect, test } from "vitest";
import { renderPhone, scrollStripToStart, type PhoneModel } from "../src/phone/render";
import { PIXEL5 } from "../src/shared/capacity";
import type { Button } from "../src/shared/config";
import type { Size, StateMsg } from "../src/shared/protocol";
import { fixtureJson } from "./fixtures";

const withPage = fixtureJson("protocol/valid/server-state.json") as StateMsg;
const noPage = fixtureJson("protocol/valid/server-state-no-page.json") as StateMsg;

let root: HTMLElement;

beforeEach(() => {
  document.body.innerHTML = '<div id="app"></div>';
  root = document.getElementById("app") as HTMLElement;
});

function render(model: Partial<PhoneModel>, size: Size = PIXEL5.portrait.page): void {
  renderPhone(root, { connected: true, state: withPage, ...model }, () => size);
}

const textButtons = (count: number, extra: { id?: string; emoji?: string } = {}): Button[] =>
  Array.from({ length: count }, (_, i) => ({
    id: `b${String(i)}`,
    type: "text" as const,
    label: `Button ${String(i)}`,
    text: "t",
    ...extra,
  }));

function renderPage(buttons: Button[], size: Size, columns: number | null = null): void {
  render({ state: { ...withPage, page: { bundleId: "x.y", columns, buttons } } }, size);
}

const pageIds = (): (string | undefined)[] =>
  [...root.querySelectorAll<HTMLElement>(".page .tile")].map((el) => el.dataset.buttonId);

const texts = (selector: string): string[] =>
  [...root.querySelectorAll(selector)].map((el) => el.textContent);

describe("renderPhone", () => {
  test("shows the frontmost app in the header", () => {
    render({});
    expect(root.querySelector(".header .app-name")?.textContent).toBe("Slack");
    expect(root.querySelector(".header .dot")?.classList.contains("dot--on")).toBe(true);
  });

  test("renders the page buttons in config order", () => {
    render({});
    expect(texts(".page .tile .label")).toEqual(["LGTM", "Jump to", "status.slack.com"]);
    expect(texts(".page .tile .emoji")).toEqual(["👍"]);
    const ids = [...root.querySelectorAll<HTMLElement>(".page .tile")].map(
      (el) => el.dataset.buttonId,
    );
    expect(ids).toEqual(["btn_3", "btn_4", "btn_5"]);
  });

  test("renders every global app in the strip, in the agent's order", () => {
    const global: Button[] = Array.from({ length: 20 }, (_, i) => ({
      id: `g${String(i)}`,
      type: "app" as const,
      bundleId: `com.example.app${String(i)}`,
    }));
    render({ state: { ...withPage, global } });
    const ids = [...root.querySelectorAll<HTMLElement>(".strip .tile")].map(
      (el) => el.dataset.buttonId,
    );
    expect(ids).toEqual(global.map((b) => b.id));
  });

  test("scrollStripToStart scrolls the strip back", () => {
    render({});
    const strip = root.querySelector<HTMLElement>(".strip");
    if (!strip) throw new Error("no strip");
    strip.scrollLeft = 120;
    scrollStripToStart(root);
    expect(strip.scrollLeft).toBe(0);
  });

  test("a web-page button shows the page app's icon and the site's host", () => {
    renderPage([{ id: "w", type: "url", url: "https://www.example.com/a" }], PIXEL5.portrait.page);
    const tile = root.querySelector('.page .tile[data-button-id="w"]');
    expect(tile?.querySelector("img")?.getAttribute("src")).toBe("/icons/x.y.png?size=128");
    expect(tile?.querySelector(".label")?.textContent).toBe("example.com");
  });

  test("renders the global strip", () => {
    render({});
    expect(root.querySelectorAll(".strip .tile")).toHaveLength(2);
    expect(texts(".strip .tile .label")[0]).toBe("Safari");
  });

  test("app button without a label falls back to the bundle ID's last part", () => {
    render({});
    expect(texts(".strip .tile .label")[1]).toBe("slackmacgap");
  });

  test("applies a custom color", () => {
    render({});
    const tile = root.querySelector<HTMLElement>('.strip .tile[data-button-id="btn_2"]');
    expect(tile?.style.getPropertyValue("--tile-color")).toBe("#4A154B");
  });

  test("without a page, the page area shows the global apps large", () => {
    render({ state: noPage });
    const page = root.querySelector(".page");
    expect(page?.classList.contains("page--fallback")).toBe(true);
    expect(texts(".page .tile .label")).toEqual(["Safari"]);
  });

  test("shows a Disconnected banner while offline", () => {
    render({ connected: false });
    expect(root.querySelector(".banner")?.textContent).toBe("Disconnected");
    expect(root.querySelector(".header .dot")?.classList.contains("dot--on")).toBe(false);
  });

  test("shows Connecting before the first state", () => {
    render({ state: null, connected: false });
    expect(root.querySelector(".page")?.textContent).toContain("Connecting");
  });

  test("shows a notice instead of buttons when given one", () => {
    render({ notice: "Not paired" });
    expect(root.querySelector(".notice")?.textContent).toBe("Not paired");
    expect(root.querySelectorAll(".tile")).toHaveLength(0);
  });

  test("renders labels as text, never HTML", () => {
    const state: StateMsg = {
      ...withPage,
      page: {
        bundleId: "x.y",
        columns: null,
        buttons: [{ id: "b", type: "text", label: "<img src=x onerror=alert(1)>", text: "t" }],
      },
    };
    render({ state });
    expect(root.querySelector('img[src="x"]')).toBeNull();
    expect(root.querySelector(".page .tile img")).toBeNull();
    expect(texts(".page .tile .label")).toEqual(["<img src=x onerror=alert(1)>"]);
  });

  test("app buttons without an emoji show the app icon", () => {
    render({});
    const img = root.querySelector<HTMLImageElement>('.strip .tile[data-button-id="btn_1"] img');
    expect(img?.getAttribute("src")).toBe("/icons/com.apple.Safari.png?size=128");
    expect(img?.alt).toBe("");
  });

  test("the header shows the frontmost app icon", () => {
    render({});
    const img = root.querySelector<HTMLImageElement>(".header img");
    expect(img?.getAttribute("src")).toBe("/icons/com.tinyspeck.slackmacgap.png?size=64");
  });
});

describe("dynamic page grid", () => {
  const portrait = PIXEL5.portrait.page;
  const landscape = PIXEL5.landscape.page;
  const page = (): HTMLElement => root.querySelector(".page") as HTMLElement;

  test.each([
    [1, portrait, "repeat(1, 393px)", "repeat(1, 393px)"],
    [4, portrait, "repeat(2, 192px)", "repeat(2, 192px)"],
    [12, landscape, "repeat(6, 110px)", "repeat(2, 110px)"],
    [55, landscape, "repeat(11, 56px)", "repeat(5, 56px)"],
  ])("%i buttons use the grid from gridFit", (count, size, cols, rows) => {
    renderPage(textButtons(count), size);
    expect(page().style.gridTemplateColumns).toBe(cols);
    expect(page().style.gridTemplateRows).toBe(rows);
    expect(root.querySelectorAll(".page .tile")).toHaveLength(count);
    expect(root.querySelector(".tile--overflow")).toBeNull();
  });

  test("honors a columns override", () => {
    renderPage(textButtons(6), portrait, 2);
    expect(page().style.gridTemplateColumns).toBe("repeat(2, 192px)");
    expect(page().style.gridTemplateRows).toBe("repeat(3, 192px)");
  });

  test("too many buttons: fills the grid and ends with a +N hidden tile, in order", () => {
    renderPage(textButtons(56), landscape);
    const ids = pageIds();
    expect(ids).toHaveLength(55);
    expect(ids.slice(0, 54)).toEqual(textButtons(54).map((b) => b.id));
    expect(ids[54]).toBeUndefined();
    const overflow = root.querySelector(".page .tile:last-child");
    expect(overflow?.classList.contains("tile--overflow")).toBe(true);
    expect(overflow?.textContent).toBe("+2 hidden — edit page");
  });

  test("the overflow tile is not a button", () => {
    renderPage(textButtons(80), portrait);
    expect(root.querySelector(".tile--overflow")?.tagName).toBe("DIV");
  });

  test("dense grids drop labels on tiles with an emoji, keep text-only labels", () => {
    const buttons = [...textButtons(30, { emoji: "🔥" }), ...textButtons(1, { id: "plain" })];
    renderPage(buttons, portrait);
    expect(page().classList.contains("page--dense")).toBe(true);
    expect(root.querySelectorAll(".page .tile .label")).toHaveLength(1);
    expect(root.querySelectorAll(".page .tile .emoji")).toHaveLength(30);
  });

  test("large tiles keep labels next to an emoji", () => {
    renderPage(textButtons(4, { emoji: "🔥" }), portrait);
    expect(page().classList.contains("page--dense")).toBe(false);
    expect(root.querySelectorAll(".page .tile .label")).toHaveLength(4);
  });

  test("the no-page fallback grids the global apps", () => {
    render({ state: noPage });
    expect(page().style.gridTemplateColumns).toBe("repeat(1, 393px)");
  });

  test("the size is read from the page area", () => {
    const seen: string[] = [];
    renderPhone(root, { connected: true, state: withPage }, (node) => {
      seen.push(node.className);
      return portrait;
    });
    expect(seen).toEqual(["page"]);
  });
});
