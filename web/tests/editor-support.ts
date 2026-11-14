// A fake agent API and helpers to drive the editor in jsdom.
import type { Viewport } from "../src/shared/capacity";
import type { Config } from "../src/shared/config";
import type { DeviceInfo, InstalledApp, SaveResult } from "../src/editor/api";
import { startEditor, type Editor } from "../src/editor/controller";
import type { Issue } from "../src/editor/validate";
import { fixtureJson } from "./fixtures";

export const specConfig = (): Config => fixtureJson("config/spec-example.json") as Config;

export const APPS: InstalledApp[] = [
  {
    bundleId: "com.apple.Notes",
    name: "Notes",
    path: "/System/Applications/Notes.app",
    running: true,
  },
  {
    bundleId: "com.apple.Safari",
    name: "Safari",
    path: "/Applications/Safari.app",
    running: false,
  },
  {
    bundleId: "com.tinyspeck.slackmacgap",
    name: "Slack",
    path: "/Applications/Slack.app",
    running: true,
  },
  {
    bundleId: "com.apple.Terminal",
    name: "Terminal",
    path: "/System/Applications/Utilities/Terminal.app",
    running: false,
  },
];

export class FakeApi {
  saved: Config[] = [];
  revoked: string[] = [];
  saveResult: ((config: Config) => SaveResult) | null = null;
  diskIssues: Issue[] = [];

  constructor(
    public stored: Config = specConfig(),
    public deviceList: DeviceInfo[] = [],
  ) {}

  config(): Promise<Config> {
    return Promise.resolve(JSON.parse(JSON.stringify(this.stored)) as Config);
  }
  diskErrors(): Promise<Issue[]> {
    return Promise.resolve(this.diskIssues);
  }
  apps(): Promise<InstalledApp[]> {
    return Promise.resolve(APPS);
  }
  devices(): Promise<DeviceInfo[]> {
    return Promise.resolve(this.deviceList);
  }
  save(config: Config): Promise<SaveResult> {
    const result = this.saveResult ? this.saveResult(config) : { ok: true as const, config };
    if (result.ok) {
      this.saved.push(config);
      this.stored = config;
    }
    return Promise.resolve(result);
  }
  revoke(id: string): Promise<boolean> {
    this.revoked.push(id);
    this.deviceList = this.deviceList.filter((d) => d.id !== id);
    return Promise.resolve(true);
  }
}

export function device(id: string, viewport?: Viewport, connected = false): DeviceInfo {
  return {
    id,
    name: `Phone ${id}`,
    pairedAt: "2026-11-13T10:00:00Z",
    connected,
    ...(viewport ? { viewport } : {}),
  };
}

export interface Harness {
  root: HTMLElement;
  api: FakeApi;
  editor: Editor;
  confirms: string[];
}

export async function mount(api = new FakeApi(), answer = true): Promise<Harness> {
  document.body.innerHTML = '<div id="app"></div>';
  const root = document.getElementById("app") as HTMLElement;
  const confirms: string[] = [];
  const editor = await startEditor({
    root,
    api,
    confirm: (message) => {
      confirms.push(message);
      return answer;
    },
  });
  return { root, api, editor, confirms };
}

/** Lets pending promise callbacks (fake API calls) run. */
export const flush = (): Promise<void> => new Promise((resolve) => setTimeout(resolve, 0));

// Same shape as querySelector<E>: the caller names the element type it expects.
// eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
export function q<T extends Element = HTMLElement>(root: ParentNode, selector: string): T {
  const node = root.querySelector<T>(selector);
  if (!node) throw new Error(`no element matches ${selector}`);
  return node;
}

export function click(root: ParentNode, selector: string): void {
  q(root, selector).click();
}

/** Sets a control's value and fires the event the editor listens for. */
export function setField(root: ParentNode, id: string, value: string | boolean): void {
  const node = q<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>(root, `#${id}`);
  if (typeof value === "boolean" && node instanceof HTMLInputElement) node.checked = value;
  else node.value = String(value);
  const toggle =
    node instanceof HTMLSelectElement ||
    (node instanceof HTMLInputElement && node.type === "checkbox");
  node.dispatchEvent(new Event(toggle ? "change" : "input", { bubbles: true }));
}

export const tileLabels = (root: ParentNode, section: string): string[] =>
  [...root.querySelectorAll(`${section} .tile[data-action="select"]`)].map(
    (el) => el.querySelector(".label")?.textContent ?? "",
  );
