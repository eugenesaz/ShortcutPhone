import { describe, expect, test } from "vitest";
import { isKeyCombo } from "../src/shared/key-combo";
import { fixtureJson } from "./fixtures";

const cases = fixtureJson("keycombos.json") as { valid: string[]; invalid: string[] };

describe("key combo (shared fixture with the Swift parser)", () => {
  test.each(cases.valid)("accepts %j", (text) => {
    expect(isKeyCombo(text)).toBe(true);
  });
  test.each(cases.invalid)("rejects %j", (text) => {
    expect(isKeyCombo(text)).toBe(false);
  });
});
