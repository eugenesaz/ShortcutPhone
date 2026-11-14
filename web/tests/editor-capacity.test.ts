import { describe, expect, test } from "vitest";
import type { Config } from "../src/shared/config";
import { FakeApi, click, device, mount, q, setField, specConfig } from "./editor-support";

const page0 = '[data-section="page"][data-page="0"]';

function withPageButtons(count: number, columns: number | null = null): Config {
  const config = specConfig();
  const page = config.pages[0];
  if (page) {
    page.columns = columns;
    page.buttons = Array.from({ length: count }, (_, i) => ({
      id: `b${String(i)}`,
      type: "text" as const,
      label: `B${String(i)}`,
      text: "t",
    }));
  }
  return config;
}

describe("editor: capacity", () => {
  test("Add is disabled at capacity, with a hint", async () => {
    const h = await mount(new FakeApi(withPageButtons(55)));
    const add = q<HTMLButtonElement>(h.root, `${page0} [data-action="add"]`);
    expect(add.disabled).toBe(true);
    expect(q(h.root, `${page0} .counter`).textContent).toBe("55 / 55");
    expect(q(h.root, `${page0} .hint`).textContent).toContain("Remove a button, or change columns");
    add.click();
    expect(h.editor.model.config.pages[0]?.buttons).toHaveLength(55);
  });

  test("Add is enabled one below capacity", async () => {
    const h = await mount(new FakeApi(withPageButtons(54)));
    click(h.root, `${page0} [data-action="add"]`);
    expect(h.editor.model.config.pages[0]?.buttons).toHaveLength(55);
    expect(q<HTMLButtonElement>(h.root, `${page0} [data-action="add"]`).disabled).toBe(true);
  });

  test("the global strip has no limit", async () => {
    const config = specConfig();
    config.global = Array.from({ length: 12 }, (_, i) => ({
      id: `g${String(i)}`,
      type: "app" as const,
      bundleId: "com.apple.Notes",
    }));
    const h = await mount(new FakeApi(config));
    click(h.root, '[data-section="global"] [data-action="add"]');
    expect(h.editor.model.config.global).toHaveLength(13);
    expect(h.root.querySelector('[data-section="global"] .hint')).toBeNull();
    expect(q<HTMLButtonElement>(h.root, '[data-action="save"]').disabled).toBe(false);
  });

  test("a columns change that would overflow is refused inline", async () => {
    // 2 columns × 5 rows (landscape Pixel 5) = 10 places.
    const h = await mount(new FakeApi(withPageButtons(12)));
    setField(h.root, "columns-0", "2");
    expect(h.editor.model.config.pages[0]?.columns).toBeNull();
    expect(q<HTMLSelectElement>(h.root, "#columns-0").value).toBe("");
    expect(q(h.root, `${page0} .field-error`).textContent).toContain(
      "2 columns hold only 10 buttons",
    );
  });

  test("a columns value that makes tiles too small is refused inline", async () => {
    const h = await mount(new FakeApi(withPageButtons(3)));
    setField(h.root, "columns-0", "7");
    expect(h.editor.model.config.pages[0]?.columns).toBeNull();
    expect(q(h.root, `${page0} .field-error`).textContent).toContain("smaller than 56 px");
  });

  test("column options show how many buttons each holds", async () => {
    const h = await mount();
    const options = [...q<HTMLSelectElement>(h.root, "#columns-0").options].map(
      (o) => o.textContent,
    );
    expect(options[0]).toBe("Auto (up to 55)");
    expect(options[2]).toBe("2 col (up to 10)");
    expect(options[8]).toBe("8 col (too narrow)");
  });

  test("a page over capacity for a newly paired smaller phone is flagged and blocks save", async () => {
    const small = {
      portrait: { page: { w: 248, h: 248 }, strip: { w: 400, h: 72 } },
      landscape: { page: { w: 248, h: 248 }, strip: { w: 72, h: 400 } },
    };
    const h = await mount(new FakeApi(withPageButtons(20), [device("s", small)]));
    expect(q(h.root, `${page0} .counter`).classList).toContain("counter--over");
    expect(q(h.root, `${page0} .field-error`).textContent).toBe(
      "20 buttons, but the page holds 16",
    );
    // Fixing it means deleting buttons; until then Save stays off.
    click(h.root, `${page0} .tile[data-index="0"]`);
    click(h.root, '[data-action="delete"]');
    expect(q<HTMLButtonElement>(h.root, '[data-action="save"]').disabled).toBe(true);
  });
});
