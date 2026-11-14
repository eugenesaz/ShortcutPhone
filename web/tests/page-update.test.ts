import { describe, expect, test, vi } from "vitest";
import { pageAssets, pageChanged } from "../src/phone/page-update";

const page = (js: string, css = "/assets/phone-A.css"): string =>
  `<!doctype html><html><head><link rel="manifest" href="/manifest.webmanifest">` +
  `<script type="module" crossorigin src="${js}"></script>` +
  `<link rel="stylesheet" crossorigin href="${css}"></head><body></body></html>`;

const parse = (html: string): Document => new DOMParser().parseFromString(html, "text/html");

const serving = (body: string, ok = true) =>
  vi.fn(() => Promise.resolve(new Response(body, { status: ok ? 200 : 500 })));

describe("pageAssets", () => {
  test("lists scripts and stylesheets, not other links", () => {
    expect(pageAssets(parse(page("/assets/phone-1.js")))).toEqual([
      "/assets/phone-1.js",
      "/assets/phone-A.css",
    ]);
  });
});

describe("pageChanged", () => {
  const current = pageAssets(parse(page("/assets/phone-1.js")));

  test("same build: no change, fetched without the cache", async () => {
    const fetchFn = serving(page("/assets/phone-1.js"));
    expect(await pageChanged(fetchFn, "/", current)).toBe(false);
    expect(fetchFn).toHaveBeenCalledWith("/", { cache: "no-store" });
  });

  test("new script or new stylesheet: changed", async () => {
    expect(await pageChanged(serving(page("/assets/phone-2.js")), "/", current)).toBe(true);
    const css = page("/assets/phone-1.js", "/assets/phone-B.css");
    expect(await pageChanged(serving(css), "/", current)).toBe(true);
  });

  test("errors and pages without assets never count as a change", async () => {
    expect(await pageChanged(serving(page("/assets/phone-2.js"), false), "/", current)).toBe(false);
    expect(await pageChanged(serving("<html></html>"), "/", current)).toBe(false);
    const offline = vi.fn(() => Promise.reject(new TypeError("offline")));
    expect(await pageChanged(offline, "/", current)).toBe(false);
  });
});
