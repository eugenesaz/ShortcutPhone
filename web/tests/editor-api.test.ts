import { describe, expect, it } from "vitest";
import { EDITOR_KEY_HEADER, EditorApi, EXPIRED_LINK } from "../src/editor/api";
import { takeEditorKey } from "../src/editor/editor-key";
import { specConfig } from "./editor-support";

interface Call {
  path: string;
  init: RequestInit | undefined;
}

function fakeFetch(status: number, body: unknown) {
  const calls: Call[] = [];
  const fetch = (path: string, init?: RequestInit) => {
    calls.push({ path, init });
    return Promise.resolve(new Response(JSON.stringify(body), { status }));
  };
  return { calls, fetch };
}

const sentKey = (call: Call | undefined) => new Headers(call?.init?.headers).get(EDITOR_KEY_HEADER);

describe("EditorApi", () => {
  it("sends the editor key on every call", async () => {
    const { calls, fetch } = fakeFetch(200, []);
    const api = new EditorApi(fetch, "k1");
    await api.apps();
    await api.devices();
    await api.diskErrors();
    await api.revoke("dev_1");
    expect(calls).toHaveLength(4);
    expect(calls.map(sentKey)).toEqual(["k1", "k1", "k1", "k1"]);
  });

  it("sends the key and JSON type on save", async () => {
    const config = specConfig();
    const { calls, fetch } = fakeFetch(200, config);
    const result = await new EditorApi(fetch, "k1").save(config);
    expect(result).toEqual({ ok: true, config });
    const headers = new Headers(calls[0]?.init?.headers);
    expect(headers.get(EDITOR_KEY_HEADER)).toBe("k1");
    expect(headers.get("Content-Type")).toBe("application/json");
  });

  it("explains a 401 as an expired editor link", async () => {
    const { fetch } = fakeFetch(401, {});
    const api = new EditorApi(fetch, "stale");
    await expect(api.config()).rejects.toThrow(EXPIRED_LINK);
    expect(await api.save(specConfig())).toEqual({ ok: false, error: EXPIRED_LINK });
  });
});

describe("takeEditorKey", () => {
  function setup(hash: string, stored: string | null = null) {
    const storage = new Map<string, string>(stored ? [["shortcutphone.editorKey", stored]] : []);
    const replaced: string[] = [];
    const env = {
      location: { hash, pathname: "/editor", search: "" },
      storage: {
        getItem: (k: string) => storage.get(k) ?? null,
        setItem: (k: string, v: string) => void storage.set(k, v),
      },
      replaceUrl: (url: string) => void replaced.push(url),
    };
    return { env, storage, replaced };
  }

  it("takes the key from the fragment, keeps it, and removes it from the address bar", () => {
    const { env, storage, replaced } = setup("#key=abc123");
    expect(takeEditorKey(env)).toBe("abc123");
    expect(storage.get("shortcutphone.editorKey")).toBe("abc123");
    expect(replaced).toEqual(["/editor"]);
  });

  it("falls back to the stored key after a reload", () => {
    const { env, replaced } = setup("", "abc123");
    expect(takeEditorKey(env)).toBe("abc123");
    expect(replaced).toEqual([]);
  });

  it("prefers a new key over the stored one", () => {
    const { env } = setup("#key=new", "old");
    expect(takeEditorKey(env)).toBe("new");
  });

  it("returns null with no key anywhere", () => {
    expect(takeEditorKey(setup("").env)).toBeNull();
    expect(takeEditorKey(setup("#key=").env)).toBeNull();
  });

  it("works when storage throws", () => {
    const { env } = setup("#key=abc");
    env.storage.setItem = () => {
      throw new Error("blocked");
    };
    expect(takeEditorKey(env)).toBe("abc");
  });
});
