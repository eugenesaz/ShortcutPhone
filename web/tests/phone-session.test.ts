import { beforeEach, describe, expect, test, vi } from "vitest";
import { startPhone, TOKEN_KEY, type PhoneDeps } from "../src/phone/session";
import type { PhoneModel } from "../src/phone/render";
import { FakeSocket } from "./fake-socket";

class MemoryStorage {
  items = new Map<string, string>();
  getItem(key: string): string | null {
    return this.items.get(key) ?? null;
  }
  setItem(key: string, value: string): void {
    this.items.set(key, value);
  }
  removeItem(key: string): void {
    this.items.delete(key);
  }
}

interface Harness {
  deps: PhoneDeps;
  storage: MemoryStorage;
  models: PhoneModel[];
  urls: string[];
  fetchMock: ReturnType<typeof vi.fn>;
}

function harness(pathname: string, search = "", token?: string): Harness {
  const storage = new MemoryStorage();
  if (token) storage.setItem(TOKEN_KEY, token);
  const models: PhoneModel[] = [];
  const urls: string[] = [];
  const fetchMock = vi.fn();
  const deps: PhoneDeps = {
    storage,
    fetch: fetchMock,
    location: { pathname, search, host: "192.168.1.20:8765", protocol: "http:" },
    replaceUrl: (path) => urls.push(path),
    render: (model) => models.push(structuredClone(model)),
    createSocket: (url) => new FakeSocket(url),
    feedback: () => undefined,
    vibrate: () => undefined,
  };
  return { deps, storage, models, urls, fetchMock };
}

const lastModel = (h: Harness): PhoneModel | undefined => h.models[h.models.length - 1];

beforeEach(() => {
  FakeSocket.all = [];
  vi.useFakeTimers();
});

describe("startPhone", () => {
  test("without a token shows Not paired and does not connect", async () => {
    const h = harness("/");
    await startPhone(h.deps);
    expect(lastModel(h)?.notice).toMatch(/Not paired/);
    expect(FakeSocket.all).toHaveLength(0);
  });

  test("with a token connects and authenticates first", async () => {
    const h = harness("/", "", "tok");
    await startPhone(h.deps);
    const socket = FakeSocket.latest();
    expect(socket.url).toBe("ws://192.168.1.20:8765/ws");
    socket.open();
    expect(socket.sent[0]).toBe('{"type":"auth","token":"tok"}');
    expect(lastModel(h)?.connected).toBe(true);
  });

  test("renders state messages", async () => {
    const h = harness("/", "", "tok");
    await startPhone(h.deps);
    FakeSocket.latest().open();
    FakeSocket.latest().receive(
      '{"type":"state","frontmost":{"bundleId":"a.b","name":"App"},"global":[],"page":null}',
    );
    expect(lastModel(h)?.state?.frontmost?.name).toBe("App");
  });

  test("4401 clears the token, shows Not paired, and stops reconnecting", async () => {
    const h = harness("/", "", "revoked");
    await startPhone(h.deps);
    FakeSocket.latest().drop(4401);
    vi.advanceTimersByTime(30_000);
    expect(FakeSocket.all).toHaveLength(1);
    expect(h.storage.getItem(TOKEN_KEY)).toBeNull();
    expect(lastModel(h)?.notice).toMatch(/Not paired/);
  });

  test("other close codes keep reconnecting", async () => {
    const h = harness("/", "", "tok");
    await startPhone(h.deps);
    FakeSocket.latest().drop(1006);
    vi.advanceTimersByTime(250);
    expect(FakeSocket.all).toHaveLength(2);
    expect(h.storage.getItem(TOKEN_KEY)).toBe("tok");
  });

  test("/pair redeems the code, stores the token, and goes to /", async () => {
    const h = harness("/pair", "?code=abc123");
    h.fetchMock.mockResolvedValue(
      new Response(JSON.stringify({ token: "new-token", deviceId: "dev_1" }), { status: 200 }),
    );
    await startPhone(h.deps);
    expect(h.fetchMock).toHaveBeenCalledWith("/api/pair", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: '{"code":"abc123"}',
    });
    expect(h.storage.getItem(TOKEN_KEY)).toBe("new-token");
    expect(h.urls).toEqual(["/"]);
    FakeSocket.latest().open();
    expect(FakeSocket.latest().sent[0]).toBe('{"type":"auth","token":"new-token"}');
  });

  test("/pair with a rejected code shows an error and keeps the old token", async () => {
    const h = harness("/pair", "?code=old", "previous");
    h.fetchMock.mockResolvedValue(new Response("invalid or expired code", { status: 400 }));
    await startPhone(h.deps);
    expect(lastModel(h)?.notice).toMatch(/Pairing failed/);
    expect(h.storage.getItem(TOKEN_KEY)).toBe("previous");
    expect(FakeSocket.all).toHaveLength(0);
  });

  test("/pair when the agent is unreachable shows an error", async () => {
    const h = harness("/pair", "?code=abc");
    h.fetchMock.mockRejectedValue(new TypeError("Failed to fetch"));
    await startPhone(h.deps);
    expect(lastModel(h)?.notice).toMatch(/Pairing failed/);
  });

  test("/pair without a code shows Not paired", async () => {
    const h = harness("/pair", "");
    await startPhone(h.deps);
    expect(lastModel(h)?.notice).toMatch(/Not paired/);
    expect(h.fetchMock).not.toHaveBeenCalled();
  });
});

describe("presses", () => {
  async function connected(token = "tok") {
    const h = harness("/", "", token);
    const feedback: { buttonId: string; ok: boolean; message?: string }[] = [];
    const vibrations: number[] = [];
    h.deps.feedback = (buttonId, ok, message) => {
      feedback.push(message === undefined ? { buttonId, ok } : { buttonId, ok, message });
    };
    h.deps.vibrate = (ms) => vibrations.push(ms);
    const phone = await startPhone(h.deps);
    if (!phone) throw new Error("not started");
    FakeSocket.latest().open();
    return { h, phone, feedback, vibrations, socket: FakeSocket.latest() };
  }

  const sentPress = (socket: FakeSocket): { pressId: string; buttonId: string } =>
    JSON.parse(socket.sent[socket.sent.length - 1] ?? "{}") as {
      pressId: string;
      buttonId: string;
    };

  test("sends a press with a fresh id and vibrates", async () => {
    const { phone, socket, vibrations } = await connected();
    phone.press("btn_1");
    phone.press("btn_1");
    const first = JSON.parse(socket.sent[1] ?? "{}") as { type: string; pressId: string };
    const second = sentPress(socket);
    expect(first.type).toBe("press");
    expect(second.buttonId).toBe("btn_1");
    expect(first.pressId).not.toBe(second.pressId);
    expect(first.pressId).toMatch(/^[0-9a-f]{32}$/);
    expect(vibrations).toEqual([15, 15]);
  });

  test("an ok result flashes the button green", async () => {
    const { phone, socket, feedback } = await connected();
    phone.press("btn_1");
    socket.receive(
      JSON.stringify({ type: "result", pressId: sentPress(socket).pressId, ok: true }),
    );
    expect(feedback).toEqual([{ buttonId: "btn_1", ok: true }]);
  });

  test("an error result flashes red with a message", async () => {
    const { phone, socket, feedback } = await connected();
    phone.press("btn_3");
    socket.receive(
      JSON.stringify({
        type: "result",
        pressId: sentPress(socket).pressId,
        ok: false,
        error: "no_accessibility",
      }),
    );
    expect(feedback).toHaveLength(1);
    expect(feedback[0]?.ok).toBe(false);
    expect(feedback[0]?.message).toMatch(/Accessibility/);
  });

  test("results for unknown press ids are ignored", async () => {
    const { socket, feedback } = await connected();
    socket.receive('{"type":"result","pressId":"other","ok":true}');
    expect(feedback).toEqual([]);
  });

  test("pressing while disconnected fails immediately", async () => {
    const { phone, socket, feedback } = await connected();
    socket.drop();
    phone.press("btn_1");
    expect(feedback).toHaveLength(1);
    expect(feedback[0]?.ok).toBe(false);
    expect(feedback[0]?.message).toMatch(/Not connected/);
  });

  test("no result within 3 s is reported as an error", async () => {
    const { phone, socket, feedback } = await connected();
    phone.press("btn_1");
    vi.advanceTimersByTime(3000);
    expect(feedback[0]?.message).toMatch(/No response/);
    socket.receive(
      JSON.stringify({ type: "result", pressId: sentPress(socket).pressId, ok: true }),
    );
    expect(feedback).toHaveLength(1);
  });
});

describe("viewport reporting", () => {
  const viewport = {
    portrait: { page: { w: 377, h: 640 }, strip: { w: 377, h: 72 } },
    landscape: { page: { w: 664, h: 351 }, strip: { w: 64, h: 377 } },
  };

  test("sends the viewport right after auth", async () => {
    const h = harness("/", "", "tok");
    h.deps.viewport = () => viewport;
    await startPhone(h.deps);
    FakeSocket.latest().open();
    const sent = FakeSocket.latest().sent;
    expect(sent).toHaveLength(2);
    expect(JSON.parse(sent[1] ?? "")).toEqual({ type: "viewport", ...viewport });
  });

  test("resizing re-renders and sends only when the viewport changed", async () => {
    const h = harness("/", "", "tok");
    let current = viewport;
    h.deps.viewport = () => current;
    const phone = await startPhone(h.deps);
    FakeSocket.latest().open();
    const renders = h.models.length;
    phone?.resized();
    expect(h.models.length).toBe(renders + 1);
    expect(FakeSocket.latest().sent).toHaveLength(2);
    current = { ...viewport, portrait: { ...viewport.portrait, page: { w: 377, h: 600 } } };
    phone?.resized();
    expect(FakeSocket.latest().sent).toHaveLength(3);
  });

  test("sends again after a reconnect", async () => {
    const h = harness("/", "", "tok");
    h.deps.viewport = () => viewport;
    await startPhone(h.deps);
    FakeSocket.latest().open();
    FakeSocket.latest().drop();
    await vi.runOnlyPendingTimersAsync();
    FakeSocket.latest().open();
    expect(FakeSocket.latest().sent).toHaveLength(2);
  });

  test("resizing while offline sends nothing", async () => {
    const h = harness("/", "", "tok");
    h.deps.viewport = () => viewport;
    const phone = await startPhone(h.deps);
    phone?.resized();
    expect(FakeSocket.latest().sent).toHaveLength(0);
  });
});
