// Editor rendering. Rebuilds the DOM from the model on every change (configs are small);
// `main.ts` restores focus afterwards. All user text goes through `textContent`.

import { effectiveCapacity, type EffectiveCapacity } from "../shared/capacity";
import { urlHost, type Button, type Config, type Page } from "../shared/config";
import type { DeviceInfo, InstalledApp } from "./api";
import {
  buttonPath,
  canAdd,
  canMove,
  getButton,
  pageCapacityOf,
  sameConfig,
  scopePath,
  type ButtonRef,
  type Scope,
} from "./state";
import { allIssues, type Issue } from "./validate";

export interface EditorModel {
  /** The draft being edited. */
  config: Config;
  /** What the agent has; the draft is dirty when it differs. */
  saved: Config;
  apps: InstalledApp[];
  devices: DeviceInfo[];
  /** Problems with config.json on disk (the agent kept the last good config). */
  diskErrors: Issue[];
  /** Problems the agent reported for the last save; cleared on the next edit. */
  serverIssues: Issue[];
  selection: ButtonRef | null;
  /** Inline errors for changes that were refused, by field path. */
  blocked: Record<string, string>;
  /** The app chosen in "Add page". */
  newPageApp: string;
  saving: boolean;
  notice: { kind: "ok" | "error"; text: string } | null;
  /** Set when the first load failed. */
  loadError?: string;
}

export function modelCapacity(model: Pick<EditorModel, "devices">): EffectiveCapacity {
  return effectiveCapacity(model.devices.flatMap((d) => (d.viewport ? [d.viewport] : [])));
}

/** Client checks plus the agent's last answer, without duplicates. */
export function modelIssues(model: EditorModel): Issue[] {
  const issues = allIssues(model.config, modelCapacity(model));
  const seen = new Set(issues.map((i) => `${i.path}\n${i.message}`));
  for (const issue of model.serverIssues) {
    if (!seen.has(`${issue.path}\n${issue.message}`)) issues.push(issue);
  }
  return issues;
}

export function isDirty(model: EditorModel): boolean {
  return !sameConfig(model.config, model.saved);
}

type Attrs = Record<string, string | number | boolean | undefined>;

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Attrs = {},
  ...children: (Node | string | null | undefined | false)[]
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === undefined || value === false) continue;
    if (key === "class") node.className = String(value);
    else if (key.startsWith("data-")) node.setAttribute(key, String(value));
    else if (value === true) node.setAttribute(key, "");
    else node.setAttribute(key, String(value));
  }
  for (const child of children) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child);
  }
  return node;
}

export function iconUrl(bundleId: string, size: number): string {
  return `/icons/${encodeURIComponent(bundleId)}.png?size=${String(size)}`;
}

function icon(bundleId: string, size: number, className = "icon"): HTMLImageElement {
  const img = el("img", { class: className, alt: "", draggable: "false" });
  img.src = iconUrl(bundleId, size);
  // A missing icon (app not installed) shouldn't show a broken-image glyph.
  img.addEventListener("error", () => {
    img.style.visibility = "hidden";
  });
  return img;
}

export function appName(apps: InstalledApp[], bundleId: string): string {
  const app = apps.find((a) => a.bundleId === bundleId);
  if (app) return app.name;
  const parts = bundleId.split(".");
  return parts[parts.length - 1] ?? bundleId;
}

function tileLabel(button: Button, apps: InstalledApp[]): string {
  if (button.label) return button.label;
  if (button.type === "app") return appName(apps, button.bundleId);
  if (button.type === "url") return urlHost(button.url);
  return "";
}

const scopeAttrs = (scope: Scope): Attrs =>
  scope.kind === "global"
    ? { "data-scope": "global" }
    : { "data-scope": "page", "data-page": scope.page };

function sameRef(a: ButtonRef | null, b: ButtonRef): boolean {
  if (!a || a.index !== b.index || a.scope.kind !== b.scope.kind) return false;
  return a.scope.kind === "global" || (b.scope.kind === "page" && a.scope.page === b.scope.page);
}

function tile(model: EditorModel, ref: ButtonRef, button: Button, issues: Issue[]): HTMLElement {
  const prefix = buttonPath(ref);
  const bad = issues.some((i) => i.path === prefix || i.path.startsWith(`${prefix}.`));
  const selected = sameRef(model.selection, ref);
  const node = el("button", {
    type: "button",
    class: `tile${selected ? " tile--selected" : ""}${bad ? " tile--error" : ""}`,
    "data-action": "select",
    "data-index": ref.index,
    "aria-pressed": selected ? "true" : "false",
    title: tileLabel(button, model.apps) || button.type,
    ...scopeAttrs(ref.scope),
  });
  if (button.color) node.style.setProperty("--tile-color", button.color);
  if (button.emoji) node.append(el("span", { class: "emoji" }, button.emoji));
  else if (button.type === "app") node.append(icon(button.bundleId, 64));
  else if (button.type === "url" && ref.scope.kind === "page") {
    node.append(icon(model.config.pages[ref.scope.page]?.bundleId ?? "", 64));
  } else node.append(el("span", { class: "kind" }, button.type === "keys" ? "⌨" : "¶"));
  const label = tileLabel(button, model.apps);
  if (label) node.append(el("span", { class: "label" }, label));
  if (button.pinned) node.append(el("span", { class: "pin", title: "Pinned" }, "📌"));
  return node;
}

function counter(count: number, max: number | null): HTMLElement {
  const over = max === null || count > max;
  return el(
    "span",
    { class: `counter${over ? " counter--over" : count === max ? " counter--full" : ""}` },
    max === null ? `${String(count)} / —` : `${String(count)} / ${String(max)}`,
  );
}

function issueText(issues: Issue[], path: string): HTMLElement | null {
  const matching = issues.filter((i) => i.path === path);
  if (matching.length === 0) return null;
  return el(
    "p",
    { class: "field-error", role: "alert" },
    matching.map((i) => i.message).join("; "),
  );
}

function tilesSection(
  model: EditorModel,
  scope: Scope,
  buttons: Button[],
  issues: Issue[],
  capacity: EffectiveCapacity,
): HTMLElement {
  const grid = el("div", { class: "tiles" });
  buttons.forEach((button, index) => {
    grid.append(tile(model, { scope, index }, button, issues));
  });
  const addable = canAdd(model.config, scope, capacity);
  const add = el(
    "button",
    {
      type: "button",
      class: "tile tile--add",
      "data-action": "add",
      disabled: !addable,
      title: addable ? "Add button" : "Full",
      ...scopeAttrs(scope),
    },
    el("span", { class: "plus" }, "+"),
    el("span", { class: "label" }, scope.kind === "global" ? "Add app" : "Add button"),
  );
  grid.append(add);
  const wrap = el("div", {}, grid);
  if (!addable) {
    wrap.append(
      el(
        "p",
        { class: "hint" },
        "This page is full on the smallest paired phone. Remove a button, or change columns.",
      ),
    );
  }
  const error = issueText(issues, scopePath(scope));
  if (error) wrap.append(error);
  return wrap;
}

function globalSection(
  model: EditorModel,
  issues: Issue[],
  capacity: EffectiveCapacity,
): HTMLElement {
  const scope: Scope = { kind: "global" };
  return el(
    "section",
    { class: "section", "data-section": "global" },
    el(
      "div",
      { class: "section-head" },
      el("h2", {}, "Global strip"),
      el(
        "span",
        { class: "counter" },
        `${String(model.config.global.length)} apps · ${String(capacity.strip)} fit without scrolling`,
      ),
    ),
    el(
      "p",
      { class: "muted" },
      "App buttons shown above every page. The strip scrolls; pinned apps come first.",
    ),
    tilesSection(model, scope, model.config.global, issues, capacity),
  );
}

function columnsSelect(
  model: EditorModel,
  page: Page,
  p: number,
  capacity: EffectiveCapacity,
): HTMLElement {
  const select = el("select", {
    id: `columns-${String(p)}`,
    "data-field": "columns",
    "data-page": p,
    "aria-label": "Columns",
  });
  const options: (number | null)[] = [null, 1, 2, 3, 4, 5, 6, 7, 8];
  for (const value of options) {
    const max = capacity.page(value);
    const name = value === null ? "Auto" : `${String(value)} col`;
    const hint = max === null ? "too narrow" : `up to ${String(max)}`;
    const option = el(
      "option",
      { value: value === null ? "" : String(value) },
      `${name} (${hint})`,
    );
    option.selected = page.columns === value;
    select.append(option);
  }
  return select;
}

function pageCard(
  model: EditorModel,
  page: Page,
  p: number,
  issues: Issue[],
  capacity: EffectiveCapacity,
): HTMLElement {
  const scope: Scope = { kind: "page", page: p };
  const path = `pages[${String(p)}]`;
  const max = pageCapacityOf(model.config, p, capacity);
  const card = el(
    "section",
    { class: "section page", "data-section": "page", "data-page": p },
    el(
      "div",
      { class: "section-head" },
      icon(page.bundleId, 64, "page-icon"),
      el(
        "div",
        { class: "page-title" },
        el("h3", {}, appName(model.apps, page.bundleId)),
        el("span", { class: "muted mono" }, page.bundleId),
      ),
      el("label", { class: "inline" }, "Columns ", columnsSelect(model, page, p, capacity)),
      counter(page.buttons.length, max),
      el(
        "div",
        { class: "page-actions" },
        el(
          "button",
          {
            type: "button",
            "data-action": "page-up",
            "data-page": p,
            disabled: p === 0,
            title: "Move up",
          },
          "↑",
        ),
        el(
          "button",
          {
            type: "button",
            "data-action": "page-down",
            "data-page": p,
            disabled: p === model.config.pages.length - 1,
            title: "Move down",
          },
          "↓",
        ),
        el(
          "button",
          { type: "button", class: "danger", "data-action": "page-delete", "data-page": p },
          "Delete page",
        ),
      ),
    ),
  );
  for (const field of ["columns", "bundleId"]) {
    const error = issueText(issues, `${path}.${field}`);
    if (error) card.append(error);
  }
  const blocked = model.blocked[`${path}.columns`];
  if (blocked) card.append(el("p", { class: "field-error", role: "alert" }, blocked));
  card.append(tilesSection(model, scope, page.buttons, issues, capacity));
  return card;
}

/** `<select>` of apps: running first, then installed. Keeps `current` even if not installed. */
function appSelect(
  apps: InstalledApp[],
  current: string,
  attrs: Attrs,
  exclude: Set<string> = new Set(),
): HTMLSelectElement {
  const select = el("select", attrs);
  if (current === "") select.append(el("option", { value: "" }, "Choose an app…"));
  if (current !== "" && !apps.some((a) => a.bundleId === current)) {
    select.append(el("option", { value: current }, `${current} (not installed)`));
  }
  const groups: [string, InstalledApp[]][] = [
    ["Running", apps.filter((a) => a.running)],
    ["Installed", apps.filter((a) => !a.running)],
  ];
  for (const [label, list] of groups) {
    const shown = list.filter((a) => !exclude.has(a.bundleId) || a.bundleId === current);
    if (shown.length === 0) continue;
    const group = el("optgroup", { label });
    for (const app of shown) group.append(el("option", { value: app.bundleId }, app.name));
    select.append(group);
  }
  select.value = current;
  return select;
}

function pagesSection(
  model: EditorModel,
  issues: Issue[],
  capacity: EffectiveCapacity,
): HTMLElement {
  const used = new Set(model.config.pages.map((page) => page.bundleId));
  const section = el(
    "section",
    { class: "pages", "data-section": "pages" },
    el("h2", {}, "App pages"),
    el("p", { class: "muted" }, "The phone shows an app's page while that app is in front."),
  );
  model.config.pages.forEach((page, p) => {
    section.append(pageCard(model, page, p, issues, capacity));
  });
  section.append(
    el(
      "div",
      { class: "add-page" },
      appSelect(
        model.apps,
        model.newPageApp,
        { id: "new-page-app", "data-field": "new-page-app", "aria-label": "App for the new page" },
        used,
      ),
      el(
        "button",
        { type: "button", "data-action": "add-page", disabled: model.newPageApp === "" },
        "Add page",
      ),
    ),
  );
  return section;
}

function field(
  label: string,
  control: HTMLElement,
  error: HTMLElement | null,
  hint?: string,
): HTMLElement {
  return el(
    "div",
    { class: "field" },
    el("label", {}, el("span", { class: "field-label" }, label), control),
    hint ? el("p", { class: "hint" }, hint) : null,
    error,
  );
}

function buttonForm(
  model: EditorModel,
  ref: ButtonRef,
  button: Button,
  issues: Issue[],
): HTMLElement {
  const path = buttonPath(ref);
  const err = (name: string): HTMLElement | null => issueText(issues, `${path}.${name}`);
  const isGlobal = ref.scope.kind === "global";
  const where =
    ref.scope.kind === "global"
      ? "Global strip"
      : appName(model.apps, model.config.pages[ref.scope.page]?.bundleId ?? "");

  const type = el("select", { id: "field-type", "data-field": "type", disabled: isGlobal });
  for (const [value, name] of [
    ["app", "Open app"],
    ["text", "Type text + Return"],
    ["keys", "Press keys"],
    ["url", "Open web page"],
  ] as const) {
    type.append(el("option", { value }, name));
  }
  type.value = button.type;

  const form = el(
    "form",
    { class: "button-form", "data-form": "button", novalidate: true },
    el("h2", {}, `${where} › button ${String(ref.index + 1)}`),
    field(
      "Action",
      type,
      err("type"),
      isGlobal ? "The global strip holds app buttons only." : undefined,
    ),
  );

  switch (button.type) {
    case "app":
      form.append(
        field(
          "App",
          appSelect(model.apps, button.bundleId, {
            id: "field-bundleId",
            "data-field": "bundleId",
          }),
          err("bundleId"),
        ),
      );
      break;
    case "text": {
      const text = el("textarea", { id: "field-text", "data-field": "text", rows: 3 });
      text.value = button.text;
      form.append(
        field("Text", text, err("text"), "Pasted into the app in front, then Return is pressed."),
      );
      break;
    }
    case "url": {
      const url = el("input", {
        id: "field-url",
        "data-field": "url",
        type: "text",
        inputmode: "url",
        placeholder: "https://example.com",
        autocomplete: "off",
        spellcheck: "false",
      });
      url.value = button.url;
      form.append(
        field(
          "Web address",
          url,
          err("url"),
          `Opens in a new ${where} tab. Put web-page buttons on a browser's page, such as Microsoft Edge or Google Chrome.`,
        ),
      );
      break;
    }
    case "keys": {
      const keys = el("input", {
        id: "field-keys",
        "data-field": "keys",
        type: "text",
        placeholder: "cmd+shift+p",
        autocomplete: "off",
        spellcheck: "false",
      });
      keys.value = button.keys;
      form.append(
        field(
          "Keys",
          keys,
          err("keys"),
          "Modifiers cmd, shift, alt, ctrl plus one key: a–z, 0–9, f1–f20, space, return, tab, esc, delete, arrows.",
        ),
      );
      break;
    }
  }

  const label = el("input", {
    id: "field-label",
    "data-field": "label",
    type: "text",
    maxlength: 40,
  });
  label.value = button.label ?? "";
  label.placeholder = button.type === "app" ? appName(model.apps, button.bundleId) : "";
  form.append(field("Label", label, err("label")));

  const emoji = el("input", {
    id: "field-emoji",
    "data-field": "emoji",
    type: "text",
    maxlength: 16,
  });
  emoji.value = button.emoji ?? "";
  form.append(
    field(
      "Emoji",
      emoji,
      err("emoji"),
      button.type === "app" ? "Optional; replaces the app icon." : "Optional.",
    ),
  );

  if (ref.scope.kind === "global") {
    const pinned = el("input", { id: "field-pinned", "data-field": "pinned", type: "checkbox" });
    pinned.checked = Boolean(button.pinned);
    form.append(
      el(
        "div",
        { class: "field" },
        el("label", { class: "inline" }, pinned, " Pin to the front"),
        el(
          "p",
          { class: "hint" },
          "Pinned apps come first in the strip. They still scroll with the others.",
        ),
      ),
    );
  }

  const colorOn = el("input", { id: "field-color-on", "data-field": "color-on", type: "checkbox" });
  colorOn.checked = button.color !== undefined;
  const color = el("input", {
    id: "field-color",
    "data-field": "color",
    type: "color",
    disabled: button.color === undefined,
    "aria-label": "Color",
  });
  color.value = button.color ?? "#3b82f6";
  form.append(
    el(
      "div",
      { class: "field" },
      el("span", { class: "field-label" }, "Color"),
      el("label", { class: "inline" }, colorOn, " Custom ", color),
      err("color"),
    ),
  );

  form.append(
    el(
      "div",
      { class: "form-actions" },
      el(
        "button",
        { type: "button", "data-action": "move-left", disabled: !canMove(model.config, ref, -1) },
        "← Move",
      ),
      el(
        "button",
        { type: "button", "data-action": "move-right", disabled: !canMove(model.config, ref, 1) },
        "Move →",
      ),
      el("button", { type: "button", class: "danger", "data-action": "delete" }, "Delete button"),
    ),
  );
  const idError = err("id");
  if (idError) form.append(idError);
  return form;
}

function panel(model: EditorModel, issues: Issue[]): HTMLElement {
  const aside = el("aside", { class: "panel" });
  const button = model.selection ? getButton(model.config, model.selection) : undefined;
  if (model.selection && button) aside.append(buttonForm(model, model.selection, button, issues));
  else {
    aside.append(
      el("p", { class: "muted placeholder" }, "Select a button to edit it, or add one with +."),
    );
  }
  return aside;
}

function viewportText(device: DeviceInfo): string {
  const vp = device.viewport;
  if (!vp) return "screen not reported yet";
  const size = (s: { w: number; h: number }): string =>
    `${String(Math.round(s.w))}×${String(Math.round(s.h))}`;
  return `page ${size(vp.portrait.page)} portrait, ${size(vp.landscape.page)} landscape`;
}

function devicesSection(model: EditorModel, capacity: EffectiveCapacity): HTMLElement {
  const reported = model.devices.filter((d) => d.viewport).length;
  const auto = capacity.page(null);
  const section = el(
    "section",
    { class: "section devices", "data-section": "devices" },
    el("h2", {}, "Paired phones"),
    el(
      "p",
      { class: "muted" },
      reported === 0
        ? "No phone has reported its screen yet, so limits use a Pixel 5. "
        : "Limits come from the smallest paired phone. ",
      `Pages hold up to ${auto === null ? "—" : String(auto)} buttons with Auto columns; about ${String(capacity.strip)} strip apps fit without scrolling.`,
    ),
  );
  if (model.devices.length === 0) {
    section.append(
      el("p", { class: "muted" }, "No phones paired. Use Pair Phone… in the menu bar."),
    );
    return section;
  }
  const list = el("ul", { class: "device-list" });
  for (const device of model.devices) {
    const paired = new Date(device.pairedAt);
    list.append(
      el(
        "li",
        { class: "device", "data-device": device.id },
        el("span", {
          class: device.connected ? "dot dot--on" : "dot",
          title: device.connected ? "Connected" : "Not connected",
        }),
        el(
          "div",
          { class: "device-info" },
          el("strong", {}, device.name),
          el(
            "span",
            { class: "muted" },
            `${device.connected ? "connected" : "offline"} · paired ${Number.isNaN(paired.getTime()) ? device.pairedAt : paired.toLocaleDateString()} · ${viewportText(device)}`,
          ),
          el("span", { class: "muted mono" }, device.id),
        ),
        el(
          "button",
          { type: "button", class: "danger", "data-action": "revoke", "data-device": device.id },
          "Revoke",
        ),
      ),
    );
  }
  section.append(list);
  return section;
}

/** Human location for an issue path, e.g. "Notes › button 2 › text". */
export function describePath(model: EditorModel, path: string): string {
  const parts: string[] = [];
  const rest = path.replace(/^global(?:\[(\d+)\])?/, (_m, i: string | undefined) => {
    parts.push("Global strip");
    if (i !== undefined) parts.push(`button ${String(Number(i) + 1)}`);
    return "";
  });
  const pageRest = rest.replace(
    /^pages\[(\d+)\](?:\.buttons(?:\[(\d+)\])?)?/,
    (_m, p: string, i: string | undefined) => {
      parts.push(appName(model.apps, model.config.pages[Number(p)]?.bundleId ?? `page ${p}`));
      if (i !== undefined) parts.push(`button ${String(Number(i) + 1)}`);
      return "";
    },
  );
  const field = pageRest.replace(/^\./, "");
  if (field) parts.push(field);
  return parts.length > 0 ? parts.join(" › ") : "config";
}

function toolbar(model: EditorModel, issues: Issue[]): HTMLElement {
  const dirty = isDirty(model);
  const status = model.saving
    ? "Saving…"
    : issues.length > 0
      ? `${String(issues.length)} problem${issues.length === 1 ? "" : "s"} to fix`
      : dirty
        ? "Unsaved changes"
        : "All changes saved";
  return el(
    "header",
    { class: "bar" },
    el("h1", {}, "ShortcutPhone"),
    el(
      "span",
      { class: `status${issues.length > 0 ? " status--error" : dirty ? " status--dirty" : ""}` },
      status,
    ),
    el(
      "button",
      { type: "button", "data-action": "revert", disabled: !dirty || model.saving },
      "Discard changes",
    ),
    el(
      "button",
      {
        type: "button",
        class: "primary",
        "data-action": "save",
        disabled:
          !dirty || model.saving || allIssues(model.config, modelCapacity(model)).length > 0,
        title: "Save (⌘S)",
      },
      "Save",
    ),
  );
}

export function renderEditor(root: HTMLElement, model: EditorModel): void {
  if (model.loadError !== undefined) {
    root.replaceChildren(
      el(
        "div",
        { class: "editor" },
        el("header", { class: "bar" }, el("h1", {}, "ShortcutPhone")),
        el("p", { class: "banner banner--error", role: "alert" }, model.loadError),
      ),
    );
    return;
  }
  const capacity = modelCapacity(model);
  const issues = modelIssues(model);
  const shell = el("div", { class: "editor" }, toolbar(model, issues));
  if (model.diskErrors.length > 0) {
    shell.append(
      el(
        "div",
        { class: "banner banner--error", role: "alert" },
        el("strong", {}, "config.json on disk is invalid. "),
        "Phones use the last good config, shown here. Saving replaces the file. ",
        el(
          "span",
          { class: "mono" },
          model.diskErrors.map((i) => `${i.path}: ${i.message}`).join("; "),
        ),
      ),
    );
  }
  if (model.notice) {
    shell.append(
      el("p", { class: `banner banner--${model.notice.kind}`, role: "status" }, model.notice.text),
    );
  }
  if (issues.length > 0) {
    const list = el("ul", { class: "issues" });
    for (const issue of issues) {
      list.append(el("li", {}, `${describePath(model, issue.path)}: ${issue.message}`));
    }
    shell.append(list);
  }
  shell.append(
    el(
      "div",
      { class: "layout" },
      el(
        "main",
        { class: "board" },
        globalSection(model, issues, capacity),
        pagesSection(model, issues, capacity),
        devicesSection(model, capacity),
      ),
      panel(model, issues),
    ),
  );
  root.replaceChildren(shell);
}
