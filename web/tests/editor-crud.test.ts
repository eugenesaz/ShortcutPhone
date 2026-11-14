import { describe, expect, test } from "vitest";
import type { Button, Config } from "../src/shared/config";
import {
  FakeApi,
  click,
  flush,
  mount,
  q,
  setField,
  specConfig,
  tileLabels,
} from "./editor-support";

const page0 = '[data-section="page"][data-page="0"]';
const pageButtons = (config: Config): Button[] => config.pages[0]?.buttons ?? [];

async function saveAndGet(harness: Awaited<ReturnType<typeof mount>>): Promise<Config> {
  click(harness.root, '[data-action="save"]');
  await flush();
  const saved = harness.api.saved[harness.api.saved.length - 1];
  if (!saved) throw new Error("nothing saved");
  return saved;
}

describe("editor: buttons", () => {
  test("add a text button, fill it in, save", async () => {
    const h = await mount();
    click(h.root, `${page0} [data-action="add"]`);
    expect(h.editor.model.selection).toEqual({ scope: { kind: "page", page: 0 }, index: 2 });
    // A new text button needs its text before it can be saved.
    expect(q<HTMLButtonElement>(h.root, '[data-action="save"]').disabled).toBe(true);
    expect(q(h.root, ".field-error").textContent).toBe("is required");

    setField(h.root, "field-label", "Ship it");
    setField(h.root, "field-text", "Shipping now 🚀");
    setField(h.root, "field-emoji", "🚀");
    expect(q(h.root, ".status").textContent).toBe("Unsaved changes");

    const saved = await saveAndGet(h);
    const added = pageButtons(saved)[2];
    expect(added).toMatchObject({
      type: "text",
      label: "Ship it",
      text: "Shipping now 🚀",
      emoji: "🚀",
    });
    expect(added?.id).toMatch(/^btn_[0-9a-f]{8}$/);
    expect(q(h.root, ".banner--ok").textContent).toContain("Saved");
    expect(q(h.root, ".status").textContent).toBe("All changes saved");
  });

  test("edit a button: change type to keys, set color, clear the emoji", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="0"]`);
    setField(h.root, "field-type", "keys");
    setField(h.root, "field-keys", "cmd+shift+p");
    setField(h.root, "field-emoji", "");
    setField(h.root, "field-color-on", true);
    setField(h.root, "field-color", "#ff0000");
    const saved = await saveAndGet(h);
    expect(pageButtons(saved)[0]).toEqual({
      id: "btn_3",
      type: "keys",
      label: "LGTM",
      keys: "cmd+shift+p",
      color: "#ff0000",
    });
  });

  test("turning the color off removes it", async () => {
    const h = await mount();
    click(h.root, '[data-section="global"] .tile[data-index="1"]');
    setField(h.root, "field-color-on", false);
    const saved = await saveAndGet(h);
    expect(saved.global[1]).toEqual({
      id: "btn_2",
      type: "app",
      bundleId: "com.tinyspeck.slackmacgap",
    });
  });

  test("delete a button", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="0"]`);
    click(h.root, '[data-action="delete"]');
    expect(h.editor.model.selection).toBeNull();
    const saved = await saveAndGet(h);
    expect(pageButtons(saved).map((b) => b.id)).toEqual(["btn_4"]);
  });

  test("reorder buttons; selection follows", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="0"]`);
    expect(q<HTMLButtonElement>(h.root, '[data-action="move-left"]').disabled).toBe(true);
    click(h.root, '[data-action="move-right"]');
    expect(tileLabels(h.root, page0)).toEqual(["Jump to", "LGTM"]);
    expect(h.editor.model.selection?.index).toBe(1);
    expect(q<HTMLButtonElement>(h.root, '[data-action="move-right"]').disabled).toBe(true);
    const saved = await saveAndGet(h);
    expect(pageButtons(saved).map((b) => b.id)).toEqual(["btn_4", "btn_3"]);
  });

  test("global buttons are app-only and pick an app from the list", async () => {
    const h = await mount();
    click(h.root, '[data-section="global"] [data-action="add"]');
    expect(q<HTMLSelectElement>(h.root, "#field-type").disabled).toBe(true);
    // Defaults to a running app that isn't in the strip yet.
    expect(q<HTMLSelectElement>(h.root, "#field-bundleId").value).toBe("com.apple.Notes");
    setField(h.root, "field-bundleId", "com.apple.Terminal");
    const saved = await saveAndGet(h);
    expect(saved.global[2]).toMatchObject({ type: "app", bundleId: "com.apple.Terminal" });
  });

  test("an app not installed stays selectable", async () => {
    const config = specConfig();
    config.global[0] = { id: "btn_1", type: "app", bundleId: "com.example.gone" };
    const h = await mount(new FakeApi(config));
    click(h.root, '[data-section="global"] .tile[data-index="0"]');
    const select = q<HTMLSelectElement>(h.root, "#field-bundleId");
    expect(select.value).toBe("com.example.gone");
    expect(select.selectedOptions[0]?.textContent).toContain("not installed");
  });

  test("invalid keys show inline and block save", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="1"]`);
    setField(h.root, "field-keys", "cmd+nope");
    expect(q(h.root, ".field .field-error").textContent).toContain("is not a key combo");
    expect(q(h.root, `${page0} .tile[data-index="1"]`).classList).toContain("tile--error");
    expect(q<HTMLButtonElement>(h.root, '[data-action="save"]').disabled).toBe(true);
    await h.editor.save();
    expect(h.api.saved).toEqual([]);
    expect(q(h.root, ".issues").textContent).toContain("Slack › button 2 › keys");
  });

  test("a text button without label or emoji is invalid", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="0"]`);
    setField(h.root, "field-label", "");
    setField(h.root, "field-emoji", "");
    expect(q(h.root, ".issues").textContent).toContain("needs a label or an emoji");
  });

  test("typing keeps focus in the field", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="0"]`);
    const label = q<HTMLInputElement>(h.root, "#field-label");
    label.focus();
    setField(h.root, "field-label", "LGTM!");
    const after = q<HTMLInputElement>(h.root, "#field-label");
    expect(after).not.toBe(label); // re-rendered
    expect(document.activeElement).toBe(after);
    expect(after.value).toBe("LGTM!");
  });

  test("discard changes goes back to the saved config", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="0"]`);
    click(h.root, '[data-action="delete"]');
    click(h.root, '[data-action="revert"]');
    expect(h.confirms).toHaveLength(1);
    expect(tileLabels(h.root, page0)).toEqual(["LGTM", "Jump to"]);
    expect(q(h.root, ".status").textContent).toBe("All changes saved");
  });
});

describe("editor: web-page buttons", () => {
  test("turn a page button into a web page and save", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="1"]`);
    setField(h.root, "field-type", "url");
    expect(q<HTMLInputElement>(h.root, "#field-url").value).toBe("https://");
    expect(q(h.root, ".field .field-error").textContent).toContain("web address");
    setField(h.root, "field-url", "https://jira.example.com/board");
    setField(h.root, "field-label", "");
    expect(tileLabels(h.root, page0)[1]).toBe("jira.example.com");
    const saved = await saveAndGet(h);
    expect(pageButtons(saved)[1]).toEqual({
      id: "btn_4",
      type: "url",
      url: "https://jira.example.com/board",
    });
  });

  test("the hint names the page's browser", async () => {
    const config = specConfig();
    config.pages[0] = {
      bundleId: "com.microsoft.edgemac",
      columns: null,
      buttons: [{ id: "w", type: "url", url: "https://example.com" }],
    };
    const h = await mount(new FakeApi(config));
    click(h.root, `${page0} .tile[data-index="0"]`);
    expect(q(h.root, ".field .hint").textContent).toContain("new edgemac tab");
    expect(
      q<HTMLImageElement>(h.root, `${page0} .tile[data-index="0"] img`).getAttribute("src"),
    ).toBe("/icons/com.microsoft.edgemac.png?size=64");
  });

  test("not offered in the global strip", async () => {
    const h = await mount();
    click(h.root, '[data-section="global"] .tile[data-index="0"]');
    expect(q<HTMLSelectElement>(h.root, "#field-type").disabled).toBe(true);
  });
});

describe("editor: pinning", () => {
  const strip = '[data-section="global"]';

  function threeApps(): Config {
    const config = specConfig();
    config.global = [
      { id: "a", type: "app", bundleId: "com.apple.Safari", pinned: true },
      { id: "b", type: "app", bundleId: "com.apple.Notes" },
      { id: "c", type: "app", bundleId: "com.apple.Terminal" },
    ];
    return config;
  }

  test("pinning moves the app to the end of the pinned group", async () => {
    const h = await mount(new FakeApi(threeApps()));
    click(h.root, `${strip} .tile[data-index="2"]`);
    setField(h.root, "field-pinned", true);
    expect(h.editor.model.selection?.index).toBe(1);
    const saved = await saveAndGet(h);
    expect(saved.global.map((b) => [b.id, Boolean(b.pinned)])).toEqual([
      ["a", true],
      ["c", true],
      ["b", false],
    ]);
  });

  test("unpinning moves it to the start of the unpinned apps and drops the flag", async () => {
    const config = threeApps();
    const b = config.global[1];
    if (b) b.pinned = true;
    const h = await mount(new FakeApi(config));
    click(h.root, `${strip} .tile[data-index="0"]`);
    setField(h.root, "field-pinned", false);
    const saved = await saveAndGet(h);
    expect(saved.global.map((x) => x.id)).toEqual(["b", "a", "c"]);
    expect("pinned" in (saved.global[1] ?? {})).toBe(false);
  });

  test("moving can't cross between pinned and unpinned apps", async () => {
    const h = await mount(new FakeApi(threeApps()));
    click(h.root, `${strip} .tile[data-index="1"]`);
    expect(q<HTMLButtonElement>(h.root, '[data-action="move-left"]').disabled).toBe(true);
    expect(q<HTMLButtonElement>(h.root, '[data-action="move-right"]').disabled).toBe(false);
    click(h.root, '[data-action="move-left"]');
    expect(h.editor.model.config.global.map((x) => x.id)).toEqual(["a", "b", "c"]);
  });

  test("page buttons have no pin toggle", async () => {
    const h = await mount();
    click(h.root, `${page0} .tile[data-index="0"]`);
    expect(h.root.querySelector("#field-pinned")).toBeNull();
  });
});

describe("editor: pages", () => {
  test("add a page from the app picker", async () => {
    const h = await mount();
    const picker = q<HTMLSelectElement>(h.root, "#new-page-app");
    // Slack already has a page.
    expect([...picker.options].map((o) => o.value)).not.toContain("com.tinyspeck.slackmacgap");
    expect(q<HTMLButtonElement>(h.root, '[data-action="add-page"]').disabled).toBe(true);
    setField(h.root, "new-page-app", "com.apple.Notes");
    click(h.root, '[data-action="add-page"]');
    expect(q(h.root, '[data-section="page"][data-page="1"] h3').textContent).toBe("Notes");
    const saved = await saveAndGet(h);
    expect(saved.pages[1]).toEqual({ bundleId: "com.apple.Notes", columns: null, buttons: [] });
  });

  test("reorder and delete pages", async () => {
    const config = specConfig();
    config.pages.push({ bundleId: "com.apple.Notes", columns: 2, buttons: [] });
    const h = await mount(new FakeApi(config));
    click(h.root, '[data-section="page"][data-page="1"] [data-action="page-up"]');
    expect(q(h.root, '[data-section="page"][data-page="0"] h3').textContent).toBe("Notes");
    // An empty page goes without asking; one with buttons asks first.
    click(h.root, '[data-section="page"][data-page="0"] [data-action="page-delete"]');
    expect(h.confirms).toEqual([]);
    click(h.root, '[data-section="page"][data-page="0"] [data-action="page-delete"]');
    expect(h.confirms).toHaveLength(1);
    expect(h.root.querySelectorAll('[data-section="page"]')).toHaveLength(0);
    const saved = await saveAndGet(h);
    expect(saved.pages).toEqual([]);
  });

  test("set columns", async () => {
    const h = await mount();
    setField(h.root, "columns-0", "3");
    const saved = await saveAndGet(h);
    expect(saved.pages[0]?.columns).toBe(3);
  });
});

describe("editor: saving", () => {
  test("a 422 from the agent shows on the matching field", async () => {
    const api = new FakeApi();
    api.saveResult = () => ({
      ok: false,
      issues: [{ path: "pages[0].buttons[1].keys", message: "rejected by the agent" }],
    });
    const h = await mount(api);
    click(h.root, `${page0} .tile[data-index="1"]`);
    setField(h.root, "field-keys", "cmd+j");
    click(h.root, '[data-action="save"]');
    await flush();
    expect(q(h.root, ".banner--error").textContent).toContain("rejected the config");
    expect(q(h.root, ".field .field-error").textContent).toBe("rejected by the agent");
    expect(q(h.root, `${page0} .tile[data-index="1"]`).classList).toContain("tile--error");
    // Editing again clears the agent's stale answer.
    setField(h.root, "field-keys", "cmd+l");
    expect(h.root.querySelector(".field .field-error")).toBeNull();
  });

  test("a 422 on a page's buttons shows under that page", async () => {
    const api = new FakeApi();
    api.saveResult = () => ({
      ok: false,
      issues: [{ path: "pages[0].buttons", message: "3 buttons, but the page holds 2" }],
    });
    const h = await mount(api);
    setField(h.root, "columns-0", "2");
    click(h.root, '[data-action="save"]');
    await flush();
    expect(q(h.root, `${page0} .field-error`).textContent).toBe("3 buttons, but the page holds 2");
  });

  test("a network failure is reported and nothing is lost", async () => {
    const api = new FakeApi();
    api.saveResult = () => ({ ok: false, error: "The agent isn't running." });
    const h = await mount(api);
    setField(h.root, "columns-0", "2");
    click(h.root, '[data-action="save"]');
    await flush();
    expect(q(h.root, ".banner--error").textContent).toBe("The agent isn't running.");
    expect(h.editor.model.config.pages[0]?.columns).toBe(2);
    expect(q(h.root, ".status").textContent).toBe("Unsaved changes");
  });
});
