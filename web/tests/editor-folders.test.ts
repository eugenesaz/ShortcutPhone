import { describe, expect, test } from "vitest";
import { effectiveCapacity } from "../src/shared/capacity";
import type { Button, Config, FolderButton } from "../src/shared/config";
import { moveToScope, newButtonId, setFolderColumns } from "../src/editor/state";
import { allIssues } from "../src/editor/validate";
import { describePath } from "../src/editor/render";
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
const folderSection = '[data-section="folder"]';
const capacity = effectiveCapacity([]);

const text = (id: string): Button => ({ id, type: "text", label: id, text: `/${id}` });

function folder(buttons: Button[] = [], extra: Partial<FolderButton> = {}): FolderButton {
  return {
    id: "f1",
    type: "folder",
    label: "Social",
    afterPress: "back",
    columns: null,
    buttons,
    ...extra,
  };
}

/** The spec example with a folder appended to page 0 (index 2). */
function withFolder(buttons: Button[] = [text("in1")], extra: Partial<FolderButton> = {}): Config {
  const config = specConfig();
  config.pages[0]?.buttons.push(folder(buttons, extra));
  return config;
}

async function saveAndGet(h: Awaited<ReturnType<typeof mount>>): Promise<Config> {
  click(h.root, '[data-action="save"]');
  await flush();
  const saved = h.api.saved[h.api.saved.length - 1];
  if (!saved) throw new Error("nothing saved");
  return saved;
}

describe("editor: folders", () => {
  test("Add folder makes an empty folder, selects it and shows its contents", async () => {
    const h = await mount();
    click(h.root, `${page0} [data-action="add-folder"]`);
    expect(h.editor.model.selection).toEqual({ scope: { kind: "page", page: 0 }, index: 2 });
    expect(q(h.root, `${page0} .tile--folder .folder-badge`).textContent).toBe("0");
    expect(q(h.root, `${folderSection} .counter`).textContent).toMatch(/^0 \/ \d+$/);
    expect(q<HTMLSelectElement>(h.root, "#field-afterPress").value).toBe("back");
    const saved = await saveAndGet(h);
    expect(saved.pages[0]?.buttons[2]).toMatchObject({
      type: "folder",
      label: "New folder",
      afterPress: "back",
      columns: null,
      buttons: [],
    });
  });

  test("add a button inside a folder, then set the folder to stay open", async () => {
    const h = await mount(new FakeApi(withFolder([])));
    click(h.root, `${page0} .tile[data-index="2"]`);
    click(h.root, `${folderSection} [data-action="add"]`);
    expect(h.editor.model.selection).toEqual({
      scope: { kind: "folder", page: 0, folder: 2 },
      index: 0,
    });
    // The folder stays expanded while one of its buttons is selected.
    expect(h.root.querySelector(folderSection)).not.toBeNull();
    expect(q(h.root, ".button-form h2").textContent).toBe("Slack › Social › button 1");
    // Folders can't hold folders.
    expect(h.root.querySelector('#field-type option[value="folder"]')).toBeNull();
    setField(h.root, "field-text", "/dance");
    click(h.root, `${page0} .tile[data-index="2"]`);
    setField(h.root, "field-afterPress", "stay");
    const saved = await saveAndGet(h);
    expect(saved.pages[0]?.buttons[2]).toMatchObject({
      afterPress: "stay",
      buttons: [{ type: "text", text: "/dance" }],
    });
  });

  test("Move to puts a page button into a folder and back", async () => {
    const h = await mount(new FakeApi(withFolder()));
    click(h.root, `${page0} .tile[data-index="0"]`);
    setField(h.root, "field-move-to", "folder:2");
    // The folder is now at index 1 on the page, and the moved button is selected inside it.
    expect(h.editor.model.selection).toEqual({
      scope: { kind: "folder", page: 0, folder: 1 },
      index: 1,
    });
    expect(tileLabels(h.root, folderSection)).toEqual(["in1", "LGTM"]);
    setField(h.root, "field-move-to", "page");
    expect(h.editor.model.selection).toEqual({ scope: { kind: "page", page: 0 }, index: 2 });
    const saved = await saveAndGet(h);
    expect(saved.pages[0]?.buttons.map((b) => b.id)).toEqual(["btn_4", "f1", "btn_3"]);
  });

  test("folders get no Move to menu: they can't nest", async () => {
    const h = await mount(new FakeApi(withFolder()));
    click(h.root, `${page0} .tile[data-index="2"]`);
    expect(h.root.querySelector("#field-move-to")).toBeNull();
  });

  test("deleting a folder with buttons asks first", async () => {
    const h = await mount(new FakeApi(withFolder()), false);
    click(h.root, `${page0} .tile[data-index="2"]`);
    click(h.root, '[data-action="delete"]');
    expect(h.confirms).toEqual(["Delete this folder and its 1 buttons?"]);
    expect(h.editor.model.config.pages[0]?.buttons).toHaveLength(3);
  });

  test("turning a folder with buttons into a button asks first", async () => {
    const h = await mount(new FakeApi(withFolder()), false);
    click(h.root, `${page0} .tile[data-index="2"]`);
    setField(h.root, "field-type", "text");
    expect(h.confirms[0]).toMatch(/Its 1 buttons are deleted/);
    expect(h.editor.model.config.pages[0]?.buttons[2]?.type).toBe("folder");
    expect(q<HTMLSelectElement>(h.root, "#field-type").value).toBe("folder");
  });

  test("global buttons can't become folders", async () => {
    const h = await mount();
    click(h.root, '[data-section="global"] .tile[data-index="0"]');
    expect(h.root.querySelector('#field-type option[value="folder"]')).toBeNull();
  });

  test("a full folder disables Add and shows a hint", async () => {
    const max = capacity.folder(null) ?? 0;
    const full = Array.from({ length: max }, (_, i) => text(`x${String(i)}`));
    const h = await mount(new FakeApi(withFolder(full)));
    click(h.root, `${page0} .tile[data-index="2"]`);
    expect(q<HTMLButtonElement>(h.root, `${folderSection} [data-action="add"]`).disabled).toBe(
      true,
    );
    expect(q(h.root, `${folderSection} .hint`).textContent).toMatch(/This folder is full/);
  });

  test("folder columns that leave too few places are refused", async () => {
    const buttons = Array.from({ length: 10 }, (_, i) => text(`x${String(i)}`));
    const h = await mount(new FakeApi(withFolder(buttons)));
    click(h.root, `${page0} .tile[data-index="2"]`);
    setField(h.root, "field-folder-columns", "1");
    expect(q(h.root, ".field-error").textContent).toMatch(/hold only \d+ buttons in a folder/);
    expect(h.editor.model.config.pages[0]?.buttons[2]).toMatchObject({ columns: null });
  });
});

describe("folder state operations", () => {
  test("moving into a full folder is refused", () => {
    const max = capacity.folder(null) ?? 0;
    const config = withFolder(Array.from({ length: max }, (_, i) => text(`x${String(i)}`)));
    const result = moveToScope(
      config,
      { scope: { kind: "page", page: 0 }, index: 0 },
      { kind: "folder", page: 0, folder: 2 },
      capacity,
    );
    expect(result).toEqual({ error: expect.stringMatching(/folder is full/) as unknown });
  });

  test("moving to another page is refused", () => {
    const config = withFolder();
    config.pages.push({ bundleId: "com.apple.Notes", columns: null, buttons: [] });
    const result = moveToScope(
      config,
      { scope: { kind: "page", page: 0 }, index: 0 },
      { kind: "page", page: 1 },
      capacity,
    );
    expect("error" in result).toBe(true);
  });

  test("setFolderColumns refuses columns that make tiles too small", () => {
    const result = setFolderColumns(
      withFolder(),
      { scope: { kind: "page", page: 0 }, index: 2 },
      8,
      capacity,
    );
    expect(result).toEqual({ error: expect.stringMatching(/smaller than 56 px/) as unknown });
  });

  test("new ids avoid ids inside folders", () => {
    const config = withFolder([text("btn_00000000")]);
    const draws = [0, 0.5];
    expect(newButtonId(config, () => draws.shift() ?? 0.25)).toBe("btn_80000000");
  });
});

describe("folder validation (mirrors the agent)", () => {
  const paths = (config: Config): string[] => allIssues(config, capacity).map((i) => i.path);

  test("a valid folder has no issues", () => {
    expect(paths(withFolder())).toEqual([]);
  });

  test("folders can't be global or nested, and need a face", () => {
    const config = withFolder([folder([], { id: "f2" })]);
    delete (config.pages[0]?.buttons[2] as Partial<FolderButton>).label;
    config.global.push(folder([], { id: "g1" }));
    expect(paths(config)).toEqual([
      "global[2].type",
      "pages[0].buttons[2].label",
      "pages[0].buttons[2].buttons[0].type",
    ]);
  });

  test("buttons inside are checked, ids are unique across folders", () => {
    const config = withFolder([
      { ...text("btn_3") },
      { id: "k", type: "keys", label: "K", keys: "" },
    ]);
    expect(paths(config)).toEqual([
      "pages[0].buttons[2].buttons[0].id",
      "pages[0].buttons[2].buttons[1].keys",
    ]);
  });

  test("over-capacity folders and too-narrow folder columns are reported", () => {
    const max = capacity.folder(null) ?? 0;
    const over = withFolder(Array.from({ length: max + 1 }, (_, i) => text(`x${String(i)}`)));
    expect(paths(over)).toEqual(["pages[0].buttons[2].buttons"]);
    expect(paths(withFolder([], { columns: 8 }))).toEqual(["pages[0].buttons[2].columns"]);
  });

  test("issue paths inside folders read naturally", async () => {
    const h = await mount(new FakeApi(withFolder()));
    expect(describePath(h.editor.model, "pages[0].buttons[2].buttons[0].text")).toBe(
      "Slack › Social › button 1 › text",
    );
    expect(describePath(h.editor.model, "pages[0].buttons[2].columns")).toBe(
      "Slack › Social › columns",
    );
  });
});
