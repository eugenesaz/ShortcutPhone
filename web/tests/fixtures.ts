// Reads the shared fixtures in Tests/Fixtures (also used by the Swift suite).
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

export const FIXTURES = join(import.meta.dirname, "..", "..", "Tests", "Fixtures");

export function fixtureNames(folder: string, prefix: string): string[] {
  return readdirSync(join(FIXTURES, folder))
    .filter((name) => name.startsWith(prefix) && name.endsWith(".json"))
    .sort();
}

export function readFixture(path: string): string {
  return readFileSync(join(FIXTURES, path), "utf8");
}

export function fixtureJson(path: string): unknown {
  return JSON.parse(readFixture(path));
}
