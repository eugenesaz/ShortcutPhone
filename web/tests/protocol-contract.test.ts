import { describe, expect, test } from "vitest";
import { isConfig } from "../src/shared/config";
import { authMsg, parseServerMsg, pressMsg, viewportMsg } from "../src/shared/protocol";
import { fixtureJson, fixtureNames, readFixture } from "./fixtures";

describe("server messages", () => {
  const valid = fixtureNames("protocol/valid", "server-");
  const invalid = fixtureNames("protocol/invalid", "server-");

  test("fixtures exist", () => {
    expect(valid.length).toBeGreaterThanOrEqual(7);
    expect(invalid.length).toBeGreaterThanOrEqual(4);
  });

  test.each(valid)("accepts %s", (name) => {
    const raw = readFixture(`protocol/valid/${name}`);
    expect(parseServerMsg(raw)).toEqual(JSON.parse(raw));
  });

  test.each(invalid)("rejects %s", (name) => {
    expect(parseServerMsg(readFixture(`protocol/invalid/${name}`))).toBeNull();
  });

  test("rejects non-JSON", () => {
    expect(parseServerMsg("not json")).toBeNull();
    expect(parseServerMsg("[]")).toBeNull();
  });
});

describe("client messages match fixtures", () => {
  test("auth", () => {
    const fixture = fixtureJson("protocol/valid/client-auth.json") as { token: string };
    expect(authMsg(fixture.token)).toEqual(fixture);
  });

  test("press", () => {
    const fixture = fixtureJson("protocol/valid/client-press.json") as {
      pressId: string;
      buttonId: string;
    };
    expect(pressMsg(fixture.pressId, fixture.buttonId)).toEqual(fixture);
  });

  test("viewport", () => {
    const fixture = fixtureJson("protocol/valid/client-viewport.json");
    expect(
      viewportMsg(
        { page: { w: 393, h: 700 }, strip: { w: 393, h: 72 } },
        { page: { w: 700.5, h: 345 }, strip: { w: 72, h: 393 } },
      ),
    ).toEqual(fixture);
  });
});

describe("config", () => {
  test("accepts the spec example", () => {
    expect(isConfig(fixtureJson("config/spec-example.json"))).toBe(true);
  });

  test("rejects a wrong version or a bad button", () => {
    const config = fixtureJson("config/spec-example.json") as Record<string, unknown>;
    expect(isConfig({ ...config, version: 2 })).toBe(false);
    expect(isConfig({ ...config, global: [{ id: "x", type: "shell" }] })).toBe(false);
  });
});
