import { describe, expect, test } from "vitest";
import { PIXEL5 } from "../src/shared/capacity";
import { FakeApi, click, device, flush, mount, q, specConfig } from "./editor-support";

describe("editor: paired phones", () => {
  test("lists devices with state, date and screen", async () => {
    const h = await mount(
      new FakeApi(specConfig(), [device("dev_a", PIXEL5, true), device("dev_b")]),
    );
    const rows = [...h.root.querySelectorAll(".device")];
    expect(rows).toHaveLength(2);
    expect(rows[0]?.textContent).toContain("Phone dev_a");
    expect(rows[0]?.textContent).toContain("connected");
    expect(rows[0]?.textContent).toContain("page 393×700 portrait, 700×345 landscape");
    expect(rows[1]?.textContent).toContain("offline");
    expect(rows[1]?.textContent).toContain("screen not reported yet");
  });

  test("revoke asks first, calls the agent and refreshes the list", async () => {
    const h = await mount(new FakeApi(specConfig(), [device("dev_a", PIXEL5, true)]));
    click(h.root, '[data-action="revoke"][data-device="dev_a"]');
    await flush();
    expect(h.confirms[0]).toContain("Revoke Phone dev_a?");
    expect(h.api.revoked).toEqual(["dev_a"]);
    expect(h.root.querySelectorAll(".device")).toHaveLength(0);
    expect(q(h.root, ".banner--ok").textContent).toContain("was revoked");
  });

  test("revoke can be cancelled", async () => {
    const h = await mount(new FakeApi(specConfig(), [device("dev_a")]), false);
    click(h.root, '[data-action="revoke"][data-device="dev_a"]');
    await flush();
    expect(h.api.revoked).toEqual([]);
  });

  test("no devices: says so and uses the Pixel 5 limits", async () => {
    const h = await mount();
    const section = q(h.root, '[data-section="devices"]');
    expect(section.textContent).toContain("No phones paired");
    expect(section.textContent).toContain("Pixel 5");
  });
});
