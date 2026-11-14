// The editor key: a per-launch secret the agent requires on every editor API call.
// The menu opens `/editor#key=<key>`. A fragment never reaches the server or its logs.

const STORAGE_KEY = "shortcutphone.editorKey";

export interface KeyEnv {
  location: Pick<Location, "hash" | "pathname" | "search">;
  storage: Pick<Storage, "getItem" | "setItem">;
  replaceUrl: (url: string) => void;
}

/** The key from the fragment (kept for reloads and dropped from the address bar), else the stored one. */
export function takeEditorKey(env: KeyEnv): string | null {
  const fromHash = new URLSearchParams(env.location.hash.replace(/^#/, "")).get("key");
  if (fromHash) {
    try {
      env.storage.setItem(STORAGE_KEY, fromHash);
    } catch {
      // Storage blocked: the key still works until the page reloads.
    }
    env.replaceUrl(env.location.pathname + env.location.search);
    return fromHash;
  }
  try {
    return env.storage.getItem(STORAGE_KEY);
  } catch {
    return null;
  }
}
