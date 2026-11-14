import type { SocketLike } from "../src/shared/ws-client";

/** In-memory WebSocket for tests. `FakeSocket.all` lists every socket created. */
export class FakeSocket implements SocketLike {
  static all: FakeSocket[] = [];
  onopen: ((event: Event) => void) | null = null;
  onclose: ((event: CloseEvent) => void) | null = null;
  onmessage: ((event: MessageEvent) => void) | null = null;
  sent: string[] = [];
  closed = false;

  constructor(readonly url: string) {
    FakeSocket.all.push(this);
  }

  static latest(): FakeSocket {
    const socket = FakeSocket.all[FakeSocket.all.length - 1];
    if (!socket) throw new Error("no socket");
    return socket;
  }

  send(data: string): void {
    this.sent.push(data);
  }

  close(): void {
    this.closed = true;
  }

  open(): void {
    this.onopen?.(new Event("open"));
  }

  drop(code = 1006): void {
    this.onclose?.(new CloseEvent("close", { code }));
  }

  receive(data: string): void {
    this.onmessage?.(new MessageEvent("message", { data }));
  }
}
