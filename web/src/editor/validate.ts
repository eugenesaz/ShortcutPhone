// Client-side copy of the agent's checks, so problems show while editing. Mirrors
// ConfigValidator.swift and EffectiveCapacity.issues in Capacity.swift. The agent re-checks
// everything on save; its answer wins.

import { MIN_TILE, type EffectiveCapacity } from "../shared/capacity";
import type { Button, Config } from "../shared/config";
import { isKeyCombo } from "../shared/key-combo";

/** One problem, pinned to a field path like `pages[0].buttons[1].keys`. */
export interface Issue {
  path: string;
  message: string;
}

/** Reverse-DNS style: letters, digits, `.`, `-`, `_`; at least one dot. */
export function isBundleId(value: string): boolean {
  return (
    value.includes(".") &&
    !value.startsWith(".") &&
    !value.endsWith(".") &&
    /^[A-Za-z0-9._-]+$/.test(value)
  );
}

/** An absolute `http`/`https` URL with a host. Mirrors `ConfigValidator.isWebURL`. */
export function isWebUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return (url.protocol === "http:" || url.protocol === "https:") && url.hostname !== "";
  } catch {
    return false;
  }
}

export function isHexColor(value: string): boolean {
  return /^#[0-9A-Fa-f]{6}$/.test(value);
}

const hasFace = (button: Button): boolean => Boolean(button.label) || Boolean(button.emoji);

export function configIssues(config: Config): Issue[] {
  const issues: Issue[] = [];
  const add = (path: string, message: string): void => {
    issues.push({ path, message });
  };
  if (config.server.port < 1 || config.server.port > 65535) {
    add("server.port", "must be between 1 and 65535");
  }

  const seenIds = new Set<string>();
  const check = (button: Button, path: string, globalStrip: boolean, inFolder = false): void => {
    if (button.id === "") add(`${path}.id`, "is required");
    else if (seenIds.has(button.id)) add(`${path}.id`, `duplicate id ${button.id}`);
    else seenIds.add(button.id);
    if (button.color !== undefined && !isHexColor(button.color)) {
      add(`${path}.color`, "must look like #RRGGBB");
    }
    switch (button.type) {
      case "app":
        if (!isBundleId(button.bundleId)) add(`${path}.bundleId`, "is not a valid bundle ID");
        return;
      case "text":
        if (globalStrip) add(`${path}.type`, "global buttons must be app buttons");
        if (button.text === "") add(`${path}.text`, "is required");
        break;
      case "url":
        if (globalStrip) add(`${path}.type`, "global buttons must be app buttons");
        if (!isWebUrl(button.url)) {
          add(`${path}.url`, "must be a web address starting with https:// or http://");
        }
        return;
      case "keys":
        if (globalStrip) add(`${path}.type`, "global buttons must be app buttons");
        if (button.keys.trim() === "") add(`${path}.keys`, "is required");
        else if (!isKeyCombo(button.keys)) {
          add(`${path}.keys`, "is not a key combo like cmd+shift+p, 1, f5 or space");
        }
        break;
      case "folder":
        if (globalStrip) add(`${path}.type`, "global buttons must be app buttons");
        if (inFolder) add(`${path}.type`, "folders can't contain folders");
        if (!hasFace(button)) add(`${path}.label`, "needs a label or an emoji");
        if (button.columns !== null && (button.columns < 1 || button.columns > 8)) {
          add(`${path}.columns`, "must be between 1 and 8");
        }
        button.buttons.forEach((inner, i) => {
          check(inner, `${path}.buttons[${String(i)}]`, false, true);
        });
        return;
    }
    if (!hasFace(button)) add(`${path}.label`, "needs a label or an emoji");
  };

  config.global.forEach((button, i) => {
    check(button, `global[${String(i)}]`, true);
  });
  const seenPages = new Set<string>();
  config.pages.forEach((page, p) => {
    const path = `pages[${String(p)}]`;
    if (!isBundleId(page.bundleId)) add(`${path}.bundleId`, "is not a valid bundle ID");
    else if (seenPages.has(page.bundleId)) {
      add(`${path}.bundleId`, `duplicate page for ${page.bundleId}`);
    } else seenPages.add(page.bundleId);
    if (page.columns !== null && (page.columns < 1 || page.columns > 8)) {
      add(`${path}.columns`, "must be between 1 and 8");
    }
    page.buttons.forEach((button, i) => {
      check(button, `${path}.buttons[${String(i)}]`, false);
    });
  });
  return issues;
}

export function capacityIssues(config: Config, capacity: EffectiveCapacity): Issue[] {
  // The global strip has no limit: it scrolls.
  const issues: Issue[] = [];
  const check = (
    path: string,
    count: number,
    columns: number | null,
    max: number | null,
    holder: string,
  ): void => {
    if (max === null) {
      issues.push({
        path: `${path}.columns`,
        message: `${String(columns ?? 0)} columns make tiles smaller than ${String(MIN_TILE)} px on a paired phone`,
      });
    } else if (count > max) {
      issues.push({
        path: `${path}.buttons`,
        message: `${String(count)} buttons, but the ${holder} holds ${String(max)}`,
      });
    }
  };
  config.pages.forEach((page, p) => {
    const path = `pages[${String(p)}]`;
    check(path, page.buttons.length, page.columns, capacity.page(page.columns), "page");
    page.buttons.forEach((button, b) => {
      if (button.type !== "folder") return;
      check(
        `${path}.buttons[${String(b)}]`,
        button.buttons.length,
        button.columns,
        capacity.folder(button.columns),
        "folder (one place is the Back tile)",
      );
    });
  });
  return issues;
}

/** Every problem the agent would report on save. */
export function allIssues(config: Config, capacity: EffectiveCapacity): Issue[] {
  return [...configIssues(config), ...capacityIssues(config, capacity)];
}
