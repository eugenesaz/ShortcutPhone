// Editor controller: owns the model, turns DOM events into state operations, re-renders.
// Kept free of globals so the tests can drive it with a fake API.

import type { Button, Config } from "../shared/config";
import type { EditorApi } from "./api";
import { isDirty, modelCapacity, renderEditor, type EditorModel } from "./render";
import {
  addButton,
  addPage,
  canAdd,
  getButton,
  moveButton,
  movePage,
  newButtonId,
  removeButton,
  removePage,
  setColumns,
  setPinned,
  updateButton,
  withFace,
  withType,
  type ButtonRef,
  type ButtonType,
  type Scope,
} from "./state";
import { allIssues } from "./validate";

export interface EditorDeps {
  root: HTMLElement;
  api: Pick<EditorApi, "config" | "diskErrors" | "apps" | "devices" | "save" | "revoke">;
  confirm: (message: string) => boolean;
}

export interface Editor {
  readonly model: EditorModel;
  save(): Promise<void>;
}

const DEFAULT_COLOR = "#3b82f6";

function scopeOf(node: HTMLElement): Scope | null {
  if (node.dataset.scope === "global") return { kind: "global" };
  if (node.dataset.scope === "page" && node.dataset.page !== undefined) {
    return { kind: "page", page: Number(node.dataset.page) };
  }
  return null;
}

/** Restores focus and caret to the control with the same id after a re-render. */
function withFocusKept(root: HTMLElement, render: () => void): void {
  const active = document.activeElement;
  const id = active instanceof HTMLElement && root.contains(active) ? active.id : "";
  const caret =
    active instanceof HTMLInputElement || active instanceof HTMLTextAreaElement
      ? { start: active.selectionStart, end: active.selectionEnd }
      : null;
  render();
  if (!id) return;
  const next = document.getElementById(id);
  if (!(next instanceof HTMLElement)) return;
  next.focus();
  if (caret && (next instanceof HTMLTextAreaElement || next instanceof HTMLInputElement)) {
    try {
      next.setSelectionRange(caret.start, caret.end);
    } catch {
      // Inputs like type=color have no caret.
    }
  }
}

export async function startEditor(deps: EditorDeps): Promise<Editor> {
  const { root, api } = deps;
  const empty: Config = { version: 1, server: { port: 8765 }, global: [], pages: [] };
  const model: EditorModel = {
    config: empty,
    saved: empty,
    apps: [],
    devices: [],
    diskErrors: [],
    serverIssues: [],
    selection: null,
    blocked: {},
    newPageApp: "",
    saving: false,
    notice: null,
  };

  const render = (): void => {
    withFocusKept(root, () => {
      renderEditor(root, model);
    });
  };

  /** Applies an edit: stale agent errors and notices go away. */
  const edit = (config: Config, selection: ButtonRef | null = model.selection): void => {
    model.config = config;
    model.selection = selection;
    model.serverIssues = [];
    model.blocked = {};
    model.notice = null;
    render();
  };

  const firstApp = (): string =>
    model.apps.find((a) => a.running)?.bundleId ?? model.apps[0]?.bundleId ?? "";

  const newButton = (scope: Scope): Button => {
    const id = newButtonId(model.config);
    if (scope.kind === "global") {
      const used = new Set(
        model.config.global.flatMap((b) => (b.type === "app" ? [b.bundleId] : [])),
      );
      const app = model.apps.find((a) => a.running && !used.has(a.bundleId)) ?? model.apps[0];
      return { id, type: "app", bundleId: app?.bundleId ?? "" };
    }
    return { id, type: "text", label: "New button", text: "" };
  };

  const refreshDevices = async (): Promise<void> => {
    model.devices = await api.devices();
  };

  const save = async (): Promise<void> => {
    if (model.saving || !isDirty(model)) return;
    if (allIssues(model.config, modelCapacity(model)).length > 0) {
      model.notice = { kind: "error", text: "Fix the problems listed above before saving." };
      render();
      return;
    }
    model.saving = true;
    model.notice = null;
    render();
    const result = await api.save(model.config);
    model.saving = false;
    if (result.ok) {
      model.config = result.config;
      model.saved = result.config;
      model.serverIssues = [];
      model.diskErrors = [];
      model.notice = { kind: "ok", text: "Saved. Connected phones are updated." };
    } else if ("issues" in result) {
      model.serverIssues = result.issues;
      model.notice = {
        kind: "error",
        text: `The agent rejected the config (${String(result.issues.length)} problem${result.issues.length === 1 ? "" : "s"}). Nothing was saved.`,
      };
    } else {
      model.notice = { kind: "error", text: result.error };
    }
    render();
  };

  const onAction = async (action: string, node: HTMLElement): Promise<void> => {
    const capacity = modelCapacity(model);
    const page = Number(node.dataset.page);
    const selection = model.selection;
    switch (action) {
      case "select": {
        const scope = scopeOf(node);
        if (!scope) return;
        model.selection = { scope, index: Number(node.dataset.index) };
        render();
        document.getElementById("field-label")?.focus();
        return;
      }
      case "add": {
        const scope = scopeOf(node);
        if (!scope || !canAdd(model.config, scope, capacity)) return;
        const added = addButton(model.config, scope, newButton(scope));
        edit(added.config, added.ref);
        document.getElementById("field-label")?.focus();
        return;
      }
      case "delete":
        if (selection) edit(removeButton(model.config, selection), null);
        return;
      case "move-left":
      case "move-right":
        if (selection) {
          const moved = moveButton(model.config, selection, action === "move-left" ? -1 : 1);
          edit(moved.config, moved.ref);
        }
        return;
      case "add-page": {
        const bundleId = model.newPageApp;
        if (bundleId === "") return;
        model.newPageApp = "";
        edit(addPage(model.config, bundleId), null);
        return;
      }
      case "page-up":
      case "page-down":
        edit(movePage(model.config, page, action === "page-up" ? -1 : 1), null);
        return;
      case "page-delete": {
        const target = model.config.pages[page];
        if (!target) return;
        if (
          target.buttons.length > 0 &&
          !deps.confirm(`Delete this page and its ${String(target.buttons.length)} buttons?`)
        ) {
          return;
        }
        edit(removePage(model.config, page), null);
        return;
      }
      case "revert":
        if (!deps.confirm("Discard all unsaved changes?")) return;
        edit(model.saved, null);
        return;
      case "save":
        await save();
        return;
      case "revoke": {
        const id = node.dataset.device ?? "";
        const device = model.devices.find((d) => d.id === id);
        if (!device) return;
        if (
          !deps.confirm(
            `Revoke ${device.name}? It disconnects now and has to scan a new QR code to pair again.`,
          )
        ) {
          return;
        }
        const ok = await api.revoke(id);
        await refreshDevices();
        model.notice = ok
          ? { kind: "ok", text: `${device.name} was revoked.` }
          : { kind: "error", text: `Couldn't revoke ${device.name}.` };
        render();
        return;
      }
    }
  };

  const onField = (fieldName: string, node: HTMLElement): void => {
    const value =
      node instanceof HTMLInputElement ||
      node instanceof HTMLSelectElement ||
      node instanceof HTMLTextAreaElement
        ? node.value
        : "";
    if (fieldName === "new-page-app") {
      model.newPageApp = value;
      render();
      return;
    }
    if (fieldName === "columns") {
      const page = Number(node.dataset.page);
      const columns = value === "" ? null : Number(value);
      const result = setColumns(model.config, page, columns, modelCapacity(model));
      if ("error" in result) {
        model.blocked = { [`pages[${String(page)}].columns`]: result.error };
        render(); // puts the select back to the current value
        return;
      }
      edit(result.config);
      return;
    }
    const ref = model.selection;
    if (!ref || !getButton(model.config, ref)) return;
    const change = (fn: (button: Button) => Button): void => {
      edit(updateButton(model.config, ref, fn));
    };
    switch (fieldName) {
      case "type":
        change((b) => withType(b, value as ButtonType, firstApp()));
        return;
      case "label":
      case "emoji":
        change((b) => withFace(b, fieldName, value));
        return;
      case "color":
        change((b) => withFace(b, "color", value));
        return;
      case "pinned": {
        const on = node instanceof HTMLInputElement && node.checked;
        const pinned = setPinned(model.config, ref.index, on);
        edit(pinned.config, pinned.ref);
        return;
      }
      case "color-on": {
        const on = node instanceof HTMLInputElement && node.checked;
        change((b) => withFace(b, "color", on ? (b.color ?? DEFAULT_COLOR) : undefined));
        return;
      }
      case "bundleId":
        change((b) => (b.type === "app" ? { ...b, bundleId: value } : b));
        return;
      case "text":
        change((b) => (b.type === "text" ? { ...b, text: value } : b));
        return;
      case "keys":
        change((b) => (b.type === "keys" ? { ...b, keys: value } : b));
        return;
      case "url":
        change((b) => (b.type === "url" ? { ...b, url: value } : b));
        return;
    }
  };

  root.addEventListener("click", (event) => {
    const target = event.target instanceof Element ? event.target.closest("[data-action]") : null;
    if (!(target instanceof HTMLElement) || !root.contains(target)) return;
    if (target instanceof HTMLButtonElement && target.disabled) return;
    void onAction(target.dataset.action ?? "", target);
  });

  // Text fields update as you type; selects and checkboxes on change.
  const fieldEvent = (event: Event): void => {
    const target = event.target;
    if (!(target instanceof HTMLElement) || !target.dataset.field) return;
    if (event instanceof InputEvent && event.isComposing) return;
    const isToggle =
      target instanceof HTMLSelectElement ||
      (target instanceof HTMLInputElement && target.type === "checkbox");
    if ((event.type === "change") !== isToggle) return;
    onField(target.dataset.field, target);
  };
  root.addEventListener("input", fieldEvent);
  root.addEventListener("change", fieldEvent);
  root.addEventListener("compositionend", fieldEvent);
  root.addEventListener("submit", (event) => {
    event.preventDefault();
  });

  try {
    const [config, diskErrors, apps, devices] = await Promise.all([
      api.config(),
      api.diskErrors(),
      api.apps(),
      api.devices(),
    ]);
    Object.assign(model, { config, saved: config, diskErrors, apps, devices });
  } catch (error) {
    model.loadError = `Can't load the config from the agent: ${error instanceof Error ? error.message : String(error)}`;
  }
  render();

  return {
    get model() {
      return model;
    },
    save,
  };
}
