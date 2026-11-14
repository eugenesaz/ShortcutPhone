// Phone UI rendering. Rebuilds the DOM from the model on every update (pages are small).

import { urlHost, type Button } from "../shared/config";
import type { Size, StateMsg } from "../shared/protocol";
import { gridFit } from "./grid-fit";

/** Below this tile edge, tiles with an emoji or icon drop their label. */
export const DENSE_TILE = 88;

export interface PhoneModel {
  connected: boolean;
  /** `null` until the first `state` arrives. */
  state: StateMsg | null;
  /** Full-screen message that replaces the buttons (e.g. "Not paired"). */
  notice?: string;
}

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  className: string,
  text?: string,
): HTMLElementTagNameMap[K] {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

export function buttonLabel(button: Button): string {
  if (button.label) return button.label;
  if (button.type === "app") {
    const parts = button.bundleId.split(".");
    return parts[parts.length - 1] ?? button.bundleId;
  }
  if (button.type === "url") return urlHost(button.url);
  return "";
}

export function iconUrl(bundleId: string, size: number): string {
  return `/icons/${encodeURIComponent(bundleId)}.png?size=${String(size)}`;
}

function icon(bundleId: string, size: number): HTMLImageElement {
  const img = el("img", "icon");
  img.src = iconUrl(bundleId, size);
  img.alt = "";
  img.draggable = false;
  return img;
}

/** `pageApp`: the page's app, whose icon a `url` button shows (it opens in that app). */
function tile(button: Button, dense = false, pageApp?: string): HTMLButtonElement {
  const node = el("button", `tile tile--${button.type}`);
  node.type = "button";
  node.dataset.buttonId = button.id;
  if (button.color) node.style.setProperty("--tile-color", button.color);
  const pictureApp =
    button.type === "app" ? button.bundleId : button.type === "url" ? pageApp : undefined;
  const hasPicture = Boolean(button.emoji) || pictureApp !== undefined;
  if (button.emoji) node.append(el("span", "emoji", button.emoji));
  else if (pictureApp !== undefined) node.append(icon(pictureApp, 128));
  const label = buttonLabel(button);
  if (label && !(dense && hasPicture)) node.append(el("span", "label", label));
  return node;
}

/** Content box of an element (client size minus padding), CSS px. */
export function contentSize(node: HTMLElement): Size {
  const style = getComputedStyle(node);
  const px = (value: string): number => parseFloat(value) || 0;
  return {
    w: node.clientWidth - px(style.paddingLeft) - px(style.paddingRight),
    h: node.clientHeight - px(style.paddingTop) - px(style.paddingBottom),
  };
}

/** Fills the page area with the largest grid that fits; never scrolls. */
function fillPage(
  node: HTMLElement,
  buttons: Button[],
  columns: number | null,
  size: Size,
  pageApp?: string,
): void {
  const fit = gridFit(buttons.length, size, columns);
  const edge = Math.floor(fit.tile);
  node.style.setProperty("--tile", `${String(edge)}px`);
  node.style.gridTemplateColumns = `repeat(${String(fit.cols)}, ${String(edge)}px)`;
  node.style.gridTemplateRows = `repeat(${String(fit.rows)}, ${String(edge)}px)`;
  const dense = edge < DENSE_TILE;
  if (dense) node.classList.add("page--dense");
  const shown = fit.overflow > 0 ? Math.max(0, fit.cols * fit.rows - 1) : buttons.length;
  node.append(...buttons.slice(0, shown).map((button) => tile(button, dense, pageApp)));
  if (fit.overflow > 0) {
    node.append(el("div", "tile tile--overflow", `+${String(fit.overflow)} hidden — edit page`));
  }
}

function header(model: PhoneModel): HTMLElement {
  const node = el("header", "header");
  const frontmost = model.state?.frontmost;
  if (frontmost) node.append(icon(frontmost.bundleId, 64));
  node.append(el("span", "app-name", frontmost?.name ?? "—"));
  node.append(el("span", model.connected ? "dot dot--on" : "dot"));
  return node;
}

/** Scrolls the global strip back to its first app. */
export function scrollStripToStart(root: HTMLElement): void {
  const strip = root.querySelector<HTMLElement>(".strip");
  if (!strip) return;
  strip.scrollLeft = 0;
  strip.scrollTop = 0;
}

export function renderPhone(
  root: HTMLElement,
  model: PhoneModel,
  measure: (node: HTMLElement) => Size = contentSize,
): void {
  const shell = el("div", model.connected ? "phone" : "phone phone--offline");
  const strip = el("nav", "strip");
  const page = el("main", "page");
  const state = model.notice === undefined ? model.state : null;
  if (state?.page) strip.append(...state.global.map((button) => tile(button)));
  if (model.notice !== undefined) page.append(el("p", "notice", model.notice));
  else if (!state) page.append(el("p", "notice", "Connecting…"));
  shell.append(header(model), strip, page);
  if (!model.connected && model.state) shell.append(el("div", "banner", "Disconnected"));
  root.replaceChildren(shell);

  // The page area's size comes from the CSS grid, not its content, so measure it empty.
  if (state) {
    const size = measure(page);
    page.classList.add("page--grid");
    if (!state.page) page.classList.add("page--fallback");
    fillPage(
      page,
      state.page?.buttons ?? state.global,
      state.page?.columns ?? null,
      size,
      state.page?.bundleId,
    );
  }
}
