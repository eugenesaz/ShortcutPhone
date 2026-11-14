import { beforeEach, describe, expect, test, vi } from "vitest";
import { flashTile } from "../src/phone/press-feedback";
import { folderHolding, renderPhone, type PhoneModel } from "../src/phone/render";
import { FOLDER_IDLE_MS, startPhone, TOKEN_KEY, type PhoneDeps } from "../src/phone/session";
import { PIXEL5 } from "../src/shared/capacity";
import type { Button, FolderButton } from "../src/shared/config";
import type { Size, StateMsg } from "../src/shared/protocol";
import { FakeSocket } from "./fake-socket";
import { fixtureJson } from "./fixtures";

/** WoW page: btn_1 keys, btn_2 "Social" folder (back: btn_3, btn_4), btn_5 "Professions" (stay). */
const wow = fixtureJson("protocol/valid/server-state-folder.json") as StateMsg;

let root: HTMLElement;

beforeEach(() => {
  document.body.innerHTML = '<div id="app"></div>';
  root = document.getElementById("app") as HTMLElement;
  FakeSocket.all = [];
  vi.useFakeTimers();
});

function render(model: Partial<PhoneModel>, size: Size = PIXEL5.portrait.page): void {
  renderPhone(root, { connected: true, state: wow, ...model }, () => size);
}

const tiles = (): HTMLElement[] => [...root.querySelectorAll<HTMLElement>(".page .tile")];

describe("rendering folders", () => {
  test("a folder tile opens a folder, not a press, and shows how many buttons it holds", () => {
    render({});
    const folder = root.querySelector<HTMLElement>('[data-folder-id="btn_2"]');
    expect(folder?.dataset.buttonId).toBeUndefined();
    expect(folder?.classList.contains("tile--folder")).toBe(true);
    expect(folder?.querySelector(".folder-badge")?.textContent).toBe("2");
    expect(folder?.querySelector(".emoji")?.textContent).toBe("💬");
    expect(folder?.getAttribute("aria-label")).toBe("Social, folder");
  });

  test("an open folder shows Back first, then its buttons", () => {
    render({ folder: "btn_2" });
    expect(tiles().map((t) => t.dataset.action ?? t.dataset.buttonId)).toEqual([
      "back",
      "btn_3",
      "btn_4",
    ]);
    expect(root.querySelector(".page")?.classList.contains("page--folder")).toBe(true);
  });

  test("the header becomes a back crumb with the app and folder names", () => {
    render({ folder: "btn_2" });
    const crumb = root.querySelector<HTMLElement>(".header .crumb");
    expect(crumb?.dataset.action).toBe("back");
    expect(crumb?.querySelector(".app-name")?.textContent).toBe("World of Warcraft");
    expect(crumb?.querySelector(".folder-name")?.textContent).toBe("💬 Social");
    expect(root.querySelector(".header .dot")).not.toBeNull();
  });

  test("an empty folder still has its Back tile", () => {
    render({ folder: "btn_5" });
    expect(tiles().map((t) => t.dataset.action)).toEqual(["back"]);
  });

  test("the folder's columns override is used, counting the Back tile", () => {
    const buttons: Button[] = Array.from({ length: 7 }, (_, i) => ({
      id: `x${String(i)}`,
      type: "keys",
      label: String(i),
      keys: String(i),
    }));
    const folder: FolderButton = {
      id: "f",
      type: "folder",
      label: "F",
      afterPress: "back",
      columns: 4,
      buttons,
    };
    const state: StateMsg = { ...wow, page: { bundleId: "x.y", columns: null, buttons: [folder] } };
    render({ state, folder: "f" });
    expect((root.querySelector(".page") as HTMLElement).style.gridTemplateColumns).toMatch(
      /^repeat\(4, /,
    );
    expect(tiles()).toHaveLength(8);
  });

  test("an overfull folder keeps Back and ends with +N hidden", () => {
    const buttons: Button[] = Array.from({ length: 12 }, (_, i) => ({
      id: `x${String(i)}`,
      type: "keys",
      label: String(i),
      keys: "1",
    }));
    const folder: FolderButton = {
      id: "f",
      type: "folder",
      label: "F",
      afterPress: "back",
      columns: null,
      buttons,
    };
    const state: StateMsg = { ...wow, page: { bundleId: "x.y", columns: null, buttons: [folder] } };
    // Room for 3 × 2 = 6 minimum tiles: Back, 4 buttons, then "+8 hidden".
    render({ state, folder: "f" }, { w: 56 * 3 + 16, h: 56 * 2 + 8 });
    const shown = tiles();
    expect(shown[0]?.dataset.action).toBe("back");
    expect(shown.slice(1, 5).map((t) => t.dataset.buttonId)).toEqual(["x0", "x1", "x2", "x3"]);
    expect(shown[5]?.textContent).toBe("+8 hidden — edit page");
  });

  test("an unknown open folder shows the page", () => {
    render({ folder: "nope" });
    expect(root.querySelector(".crumb")).toBeNull();
    expect(root.querySelector('[data-folder-id="btn_2"]')).not.toBeNull();
  });

  test("folderHolding finds the folder of an inner button", () => {
    expect(folderHolding(wow, "btn_4")?.id).toBe("btn_2");
    expect(folderHolding(wow, "btn_1")).toBeUndefined();
  });

  test("flashTile falls back to the folder tile when the button is not shown", () => {
    render({});
    expect(flashTile(root, ["btn_3", "btn_2"], true)).toBe(true);
    expect(root.querySelector('[data-folder-id="btn_2"]')?.classList.contains("tile--ok")).toBe(
      true,
    );
  });
});

describe("folder session", () => {
  async function connected() {
    const models: PhoneModel[] = [];
    const feedback: { buttonId: string; ok: boolean; folderId?: string }[] = [];
    const vibrations: number[] = [];
    const store = new Map<string, string>([[TOKEN_KEY, "tok"]]);
    const deps: PhoneDeps = {
      storage: {
        getItem: (k) => store.get(k) ?? null,
        setItem: (k, v) => store.set(k, v),
        removeItem: (k) => store.delete(k),
      },
      fetch: vi.fn(),
      location: { pathname: "/", search: "", host: "h:1", protocol: "http:" },
      replaceUrl: () => undefined,
      render: (model) => models.push(structuredClone(model)),
      createSocket: (url) => new FakeSocket(url),
      feedback: (buttonId, ok, _message, folderId) => {
        feedback.push(folderId === undefined ? { buttonId, ok } : { buttonId, ok, folderId });
      },
      vibrate: (ms) => vibrations.push(ms),
    };
    const phone = await startPhone(deps);
    if (!phone) throw new Error("not started");
    const socket = FakeSocket.latest();
    socket.open();
    socket.receive(JSON.stringify(wow));
    const folder = (): string | undefined => models[models.length - 1]?.folder;
    const lastPress = (): { pressId: string; buttonId: string } =>
      JSON.parse(socket.sent[socket.sent.length - 1] ?? "{}") as {
        pressId: string;
        buttonId: string;
      };
    return { phone, socket, folder, feedback, vibrations, lastPress };
  }

  test("opening a folder sends nothing to the Mac and gives a short vibration", async () => {
    const { phone, socket, folder, vibrations } = await connected();
    const sent = socket.sent.length;
    phone.openFolder("btn_2");
    expect(folder()).toBe("btn_2");
    expect(socket.sent).toHaveLength(sent);
    expect(vibrations).toEqual([8]);
  });

  test("an unknown folder id is ignored", async () => {
    const { phone, folder } = await connected();
    phone.openFolder("btn_1");
    expect(folder()).toBeUndefined();
  });

  test("a back folder returns to the page right after a tap", async () => {
    const { phone, folder, lastPress } = await connected();
    phone.openFolder("btn_2");
    phone.press("btn_3");
    expect(lastPress().buttonId).toBe("btn_3");
    expect(folder()).toBeUndefined();
  });

  test("a stay folder stays open after a tap", async () => {
    const { phone, socket, folder } = await connected();
    const stay = structuredClone(wow);
    const prof = stay.page?.buttons[2];
    if (prof?.type !== "folder") throw new Error("fixture changed");
    prof.buttons = [{ id: "p1", type: "keys", label: "Craft", keys: "c" }];
    socket.receive(JSON.stringify(stay));
    phone.openFolder("btn_5");
    phone.press("p1");
    expect(folder()).toBe("btn_5");
  });

  test("feedback names the folder, so the folder tile can flash after it closed", async () => {
    const { phone, socket, feedback, lastPress } = await connected();
    phone.openFolder("btn_2");
    phone.press("btn_4");
    socket.receive(JSON.stringify({ type: "result", pressId: lastPress().pressId, ok: true }));
    expect(feedback).toEqual([{ buttonId: "btn_4", ok: true, folderId: "btn_2" }]);
  });

  test("Back closes the folder", async () => {
    const { phone, folder } = await connected();
    phone.openFolder("btn_2");
    phone.closeFolder();
    expect(folder()).toBeUndefined();
  });

  test("an open folder closes after 30 s without a tap", async () => {
    const { phone, socket, folder } = await connected();
    const stay = structuredClone(wow);
    const prof = stay.page?.buttons[2];
    if (prof?.type !== "folder") throw new Error("fixture changed");
    prof.buttons = [{ id: "p1", type: "keys", label: "Craft", keys: "c" }];
    socket.receive(JSON.stringify(stay));
    phone.openFolder("btn_5");
    vi.advanceTimersByTime(FOLDER_IDLE_MS - 1000);
    phone.press("p1"); // a tap restarts the countdown
    vi.advanceTimersByTime(FOLDER_IDLE_MS - 1000);
    expect(folder()).toBe("btn_5");
    vi.advanceTimersByTime(1000);
    expect(folder()).toBeUndefined();
  });

  test("switching apps closes the folder, even when switching back", async () => {
    const { phone, socket, folder } = await connected();
    phone.openFolder("btn_2");
    socket.receive(
      JSON.stringify({ ...wow, frontmost: { bundleId: "com.apple.Safari", name: "Safari" } }),
    );
    socket.receive(JSON.stringify(wow));
    expect(folder()).toBeUndefined();
  });

  test("a config push keeps the folder open while it exists, and closes it when removed", async () => {
    const { phone, socket, folder } = await connected();
    phone.openFolder("btn_2");
    socket.receive(JSON.stringify(wow));
    expect(folder()).toBe("btn_2");
    const removed = structuredClone(wow);
    if (removed.page) removed.page.buttons = removed.page.buttons.slice(0, 1);
    socket.receive(JSON.stringify(removed));
    expect(folder()).toBeUndefined();
  });
});
