// Phone startup: pairing via /pair?code=…, then one authenticated socket to the agent.

import type { Viewport } from "../shared/capacity";
import {
  authMsg,
  pressMsg,
  viewportMsg,
  type PressError,
  type ServerMsg,
} from "../shared/protocol";
import { connectSocket, type SocketLike } from "../shared/ws-client";
import type { PhoneModel } from "./render";

export const TOKEN_KEY = "shortcutphone.token";
/** WebSocket close code for a missing, invalid or revoked token. */
export const UNAUTHORIZED = 4401;

const NOT_PAIRED = "Not paired. On the Mac, choose Pair Phone… in the menu and scan the QR code.";
/** A press with no result after this long is reported as failed. */
export const PRESS_TIMEOUT_MS = 3000;
const VIBRATE_MS = 15;

const ERROR_TEXT: Record<PressError | "offline" | "timeout", string> = {
  wrong_app: "The app changed. Try again.",
  no_accessibility: "Allow ShortcutPhone in Accessibility settings on the Mac.",
  launch_failed: "Couldn't open the app.",
  unknown_button: "That button no longer exists.",
  offline: "Not connected.",
  timeout: "No response from the Mac.",
};

/** Everything the phone touches in the browser, so tests can fake it. */
export interface PhoneDeps {
  storage: Pick<Storage, "getItem" | "setItem" | "removeItem">;
  fetch: typeof fetch;
  location: Pick<Location, "pathname" | "search" | "host" | "protocol">;
  replaceUrl: (path: string) => void;
  render: (model: PhoneModel) => void;
  createSocket?: (url: string) => SocketLike;
  /** Flash the tile; `message` is set for errors. */
  feedback: (buttonId: string, ok: boolean, message?: string) => void;
  vibrate: (ms: number) => void;
  /** Current screen layout for both orientations; read after each render. */
  viewport?: () => Viewport | null;
}

export interface Phone {
  press(buttonId: string): void;
  /** The screen size or orientation changed: re-render and report the new viewport. */
  resized(): void;
}

/** 128 random bits, hex. `crypto.randomUUID` needs HTTPS; `getRandomValues` does not. */
function newPressId(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function startPhone(deps: PhoneDeps): Promise<Phone | null> {
  const model: PhoneModel = { connected: false, state: null };
  const show = (notice: string): null => {
    model.notice = notice;
    deps.render(model);
    return null;
  };

  if (deps.location.pathname === "/pair") {
    const code = new URLSearchParams(deps.location.search).get("code");
    if (!code) return show(NOT_PAIRED);
    const token = await redeem(deps.fetch, code);
    if (!token) {
      return show("Pairing failed: the code is invalid or expired. Make a new code on the Mac.");
    }
    deps.storage.setItem(TOKEN_KEY, token);
    deps.replaceUrl("/");
  }

  const token = deps.storage.getItem(TOKEN_KEY);
  if (!token) return show(NOT_PAIRED);

  const pending = new Map<string, { buttonId: string; timer: ReturnType<typeof setTimeout> }>();
  const settle = (pressId: string, error?: keyof typeof ERROR_TEXT): void => {
    const entry = pending.get(pressId);
    if (!entry) return;
    pending.delete(pressId);
    clearTimeout(entry.timer);
    if (error) deps.feedback(entry.buttonId, false, ERROR_TEXT[error]);
    else deps.feedback(entry.buttonId, true);
  };

  let sendRaw: ((raw: string) => void) | null = null;
  let lastViewport = "";
  const reportViewport = (): void => {
    const viewport = deps.viewport?.();
    if (!sendRaw || !viewport) return;
    const raw = JSON.stringify(viewportMsg(viewport.portrait, viewport.landscape));
    if (raw === lastViewport) return;
    lastViewport = raw;
    sendRaw(raw);
  };

  const scheme = deps.location.protocol === "https:" ? "wss:" : "ws:";
  const options = {
    url: `${scheme}//${deps.location.host}/ws`,
    onOpen: (send: (raw: string) => void) => {
      send(JSON.stringify(authMsg(token)));
      // The agent handles messages in order, so the viewport arrives after auth.
      sendRaw = send;
      lastViewport = "";
    },
    onStatus: (connected: boolean) => {
      model.connected = connected;
      if (!connected) sendRaw = null;
      deps.render(model);
      if (connected) reportViewport();
    },
    onMessage: (msg: ServerMsg) => {
      if (msg.type === "state") {
        model.state = msg;
        deps.render(model);
      } else {
        settle(msg.pressId, msg.ok ? undefined : msg.error);
      }
    },
    onClose: (code: number) => {
      if (code !== UNAUTHORIZED) return true;
      deps.storage.removeItem(TOKEN_KEY);
      model.state = null;
      show(NOT_PAIRED);
      return false;
    },
  };
  const handle = connectSocket(
    deps.createSocket ? { ...options, createSocket: deps.createSocket } : options,
  );
  deps.render(model);

  return {
    press(buttonId) {
      deps.vibrate(VIBRATE_MS);
      const pressId = newPressId();
      if (!handle.send(pressMsg(pressId, buttonId))) {
        deps.feedback(buttonId, false, ERROR_TEXT.offline);
        return;
      }
      const timer = setTimeout(() => {
        settle(pressId, "timeout");
      }, PRESS_TIMEOUT_MS);
      pending.set(pressId, { buttonId, timer });
    },
    resized() {
      deps.render(model);
      reportViewport();
    },
  };
}

async function redeem(fetchFn: typeof fetch, code: string): Promise<string | null> {
  try {
    const response = await fetchFn("/api/pair", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code }),
    });
    if (!response.ok) return null;
    const body: unknown = await response.json();
    if (typeof body === "object" && body !== null && "token" in body) {
      const token: unknown = body.token;
      return typeof token === "string" && token ? token : null;
    }
    return null;
  } catch {
    return null;
  }
}
