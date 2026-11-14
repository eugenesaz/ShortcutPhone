// One WebSocket to the agent, reconnecting with exponential backoff (max 5 s).

import { parseServerMsg, type ClientMsg, type ServerMsg } from "./protocol";

/** The subset of the browser WebSocket used here, so tests can pass a fake. */
export interface SocketLike {
  onopen: ((event: Event) => void) | null;
  onclose: ((event: CloseEvent) => void) | null;
  onmessage: ((event: MessageEvent) => void) | null;
  send(data: string): void;
  close(): void;
}

export interface SocketOptions {
  url: string;
  onMessage: (msg: ServerMsg) => void;
  /** `true` when connected, `false` once per outage. */
  onStatus: (connected: boolean) => void;
  /** Runs on every (re)connect, before anything else is sent. */
  onOpen?: (send: (raw: string) => void) => void;
  /** Return `false` to stop reconnecting (e.g. 4401: not paired). */
  onClose?: (code: number) => boolean;
  createSocket?: (url: string) => SocketLike;
}

export interface SocketHandle {
  /** Sends if connected; returns whether it was sent. */
  send(msg: ClientMsg): boolean;
  stop(): void;
}

const FIRST_DELAY_MS = 250;
const MAX_DELAY_MS = 5000;

export function backoffDelay(attempt: number): number {
  return Math.min(FIRST_DELAY_MS * 2 ** attempt, MAX_DELAY_MS);
}

export function connectSocket(options: SocketOptions): SocketHandle {
  const create: (url: string) => SocketLike =
    options.createSocket ?? ((url: string) => new WebSocket(url));
  let socket: SocketLike | null = null;
  let open = false;
  let attempt = 0;
  let stopped = false;
  let reportedDown = false;
  let timer: ReturnType<typeof setTimeout> | undefined;

  function connect(): void {
    const current = create(options.url);
    socket = current;
    current.onopen = () => {
      open = true;
      attempt = 0;
      reportedDown = false;
      options.onOpen?.((raw) => {
        current.send(raw);
      });
      options.onStatus(true);
    };
    current.onmessage = (event) => {
      const data: unknown = event.data;
      if (typeof data !== "string") return;
      const msg = parseServerMsg(data);
      if (msg) options.onMessage(msg);
    };
    current.onclose = (event) => {
      if (socket !== current) return;
      open = false;
      socket = null;
      if (!reportedDown) {
        reportedDown = true;
        options.onStatus(false);
      }
      if (stopped) return;
      if (options.onClose && !options.onClose(event.code)) return;
      timer = setTimeout(connect, backoffDelay(attempt));
      attempt += 1;
    };
  }

  connect();

  return {
    send(msg) {
      if (!open || !socket) return false;
      socket.send(JSON.stringify(msg));
      return true;
    },
    stop() {
      stopped = true;
      clearTimeout(timer);
      socket?.close();
    },
  };
}
