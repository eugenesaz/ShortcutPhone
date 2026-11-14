import { beforeEach, expect, test, vi } from "vitest";
import { flashTile, showToast } from "../src/phone/press-feedback";

beforeEach(() => {
  vi.useFakeTimers();
  document.body.innerHTML =
    '<div id="app"><main class="page"><button class="tile" data-button-id="b1"></button></main></div>';
});

const root = (): HTMLElement => document.getElementById("app") as HTMLElement;
const tile = (): Element | null => root().querySelector('[data-button-id="b1"]');

test("flashTile adds and then removes the ok class", () => {
  flashTile(root(), "b1", true);
  expect(tile()?.classList.contains("tile--ok")).toBe(true);
  vi.advanceTimersByTime(400);
  expect(tile()?.classList.contains("tile--ok")).toBe(false);
});

test("flashTile marks errors", () => {
  flashTile(root(), "b1", false);
  expect(tile()?.classList.contains("tile--error")).toBe(true);
});

test("flashTile ignores buttons that are no longer shown", () => {
  expect(() => {
    flashTile(root(), "gone", true);
  }).not.toThrow();
});

test("showToast shows a message briefly", () => {
  showToast(root(), "No response");
  expect(root().querySelector(".toast")?.textContent).toBe("No response");
  vi.advanceTimersByTime(2000);
  expect(root().querySelector(".toast")).toBeNull();
});

test("a new toast replaces the old one", () => {
  showToast(root(), "one");
  showToast(root(), "two");
  expect([...root().querySelectorAll(".toast")].map((t) => t.textContent)).toEqual(["two"]);
});
