import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { backoffDelay, connectSocket } from "../src/shared/ws-client";
import { FakeSocket } from "./fake-socket";

const latest = (): FakeSocket => FakeSocket.latest();

beforeEach(() => {
  FakeSocket.all = [];
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("backoffDelay", () => {
  test("doubles from 250 ms and caps at 5 s", () => {
    expect([0, 1, 2, 3, 4, 5, 6, 10].map(backoffDelay)).toEqual([
      250, 500, 1000, 2000, 4000, 5000, 5000, 5000,
    ]);
  });
});

describe("connectSocket", () => {
  function connect() {
    const events: string[] = [];
    const messages: string[] = [];
    const handle = connectSocket({
      url: "ws://agent/ws",
      createSocket: (url) => new FakeSocket(url),
      onOpen: (send) => {
        send('{"type":"auth"}');
      },
      onMessage: (msg) => messages.push(msg.type),
      onStatus: (connected) => events.push(connected ? "up" : "down"),
    });
    return { events, messages, handle };
  }

  test("connects, runs onOpen, reports status", () => {
    const { events } = connect();
    expect(latest().url).toBe("ws://agent/ws");
    latest().open();
    expect(latest().sent).toEqual(['{"type":"auth"}']);
    expect(events).toEqual(["up"]);
  });

  test("passes parsed server messages and drops malformed ones", () => {
    const { messages } = connect();
    latest().open();
    latest().receive('{"type":"state","frontmost":null,"global":[],"page":null}');
    latest().receive("garbage");
    latest().receive('{"type":"state"}');
    expect(messages).toEqual(["state"]);
  });

  test("reconnects with growing delays capped at 5 s", () => {
    const { events } = connect();
    const delays = [250, 500, 1000, 2000, 4000, 5000, 5000];
    for (const delay of delays) {
      const count = FakeSocket.all.length;
      latest().drop();
      vi.advanceTimersByTime(delay - 1);
      expect(FakeSocket.all.length).toBe(count);
      vi.advanceTimersByTime(1);
      expect(FakeSocket.all.length).toBe(count + 1);
    }
    expect(events.every((e) => e === "down")).toBe(true);
  });

  test("resets the delay after a successful connection", () => {
    connect();
    latest().drop();
    vi.advanceTimersByTime(250);
    latest().drop();
    vi.advanceTimersByTime(500);
    latest().open();
    latest().drop();
    const count = FakeSocket.all.length;
    vi.advanceTimersByTime(250);
    expect(FakeSocket.all.length).toBe(count + 1);
  });

  test("reports down once per outage", () => {
    const { events } = connect();
    latest().open();
    latest().drop();
    vi.advanceTimersByTime(250);
    latest().drop();
    expect(events).toEqual(["up", "down"]);
  });

  test("send works only while open", () => {
    const { handle } = connect();
    expect(handle.send({ type: "press", pressId: "p", buttonId: "b" })).toBe(false);
    latest().open();
    expect(handle.send({ type: "press", pressId: "p", buttonId: "b" })).toBe(true);
    expect(latest().sent[latest().sent.length - 1]).toBe(
      '{"type":"press","pressId":"p","buttonId":"b"}',
    );
  });

  test("stop closes the socket and stops reconnecting", () => {
    const { handle } = connect();
    const socket = latest();
    handle.stop();
    expect(socket.closed).toBe(true);
    socket.drop();
    vi.advanceTimersByTime(10_000);
    expect(FakeSocket.all.length).toBe(1);
  });

  test("onClose can stop reconnecting for a given close code", () => {
    const codes: number[] = [];
    connectSocket({
      url: "ws://agent/ws",
      createSocket: (url) => new FakeSocket(url),
      onMessage: () => undefined,
      onStatus: () => undefined,
      onClose: (code) => {
        codes.push(code);
        return code !== 4401;
      },
    });
    latest().drop(4401);
    vi.advanceTimersByTime(10_000);
    expect(codes).toEqual([4401]);
    expect(FakeSocket.all.length).toBe(1);
  });
});
