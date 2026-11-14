import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";

const web = join(import.meta.dirname, "..");

interface Manifest {
  display: string;
  start_url: string;
  icons: { src: string; sizes: string; type: string; purpose: string }[];
}

const manifest = JSON.parse(
  readFileSync(join(web, "public", "manifest.webmanifest"), "utf8"),
) as Manifest;

describe("PWA manifest", () => {
  test("opens full screen at the phone page", () => {
    expect(manifest.display).toBe("standalone");
    expect(manifest.start_url).toBe("/");
  });

  test("has 192 and 512 icons plus a maskable one, and the files exist", () => {
    expect(manifest.icons.map((i) => i.sizes)).toEqual(
      expect.arrayContaining(["192x192", "512x512"]),
    );
    expect(manifest.icons.some((i) => i.purpose === "maskable")).toBe(true);
    for (const icon of manifest.icons) {
      expect(existsSync(join(web, "public", icon.src))).toBe(true);
    }
  });

  test("the phone page links it", () => {
    const html = readFileSync(join(web, "index.html"), "utf8");
    expect(html).toContain('<link rel="manifest" href="/manifest.webmanifest" />');
  });
});
