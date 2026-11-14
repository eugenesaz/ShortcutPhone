// The editor's HTTP calls. Every route is loopback-only on the agent and needs the editor key.

import type { Viewport } from "../shared/capacity";
import { isConfig, type Config } from "../shared/config";
import { isArrayOf, isRecord, isString } from "../shared/guards";
import type { Issue } from "./validate";

export interface InstalledApp {
  bundleId: string;
  name: string;
  path: string;
  running: boolean;
}

export interface DeviceInfo {
  id: string;
  name: string;
  /** ISO 8601 */
  pairedAt: string;
  viewport?: Viewport;
  connected: boolean;
}

export type SaveResult =
  { ok: true; config: Config } | { ok: false; issues: Issue[] } | { ok: false; error: string };

type Fetch = (input: string, init?: RequestInit) => Promise<Response>;

export const EDITOR_KEY_HEADER = "X-ShortcutPhone-Editor-Key";
export const EXPIRED_LINK =
  "This editor link has expired. Open the editor again from the ShortcutPhone menu.";

const isIssue = (value: unknown): value is Issue =>
  isRecord(value) && isString(value.path) && isString(value.message);

const isApp = (value: unknown): value is InstalledApp =>
  isRecord(value) &&
  isString(value.bundleId) &&
  isString(value.name) &&
  isString(value.path) &&
  typeof value.running === "boolean";

const isDevice = (value: unknown): value is DeviceInfo =>
  isRecord(value) &&
  isString(value.id) &&
  isString(value.name) &&
  isString(value.pairedAt) &&
  (value.viewport === undefined || isRecord(value.viewport)) &&
  typeof value.connected === "boolean";

export class EditorApi {
  constructor(
    private readonly fetchImpl: Fetch,
    private readonly key: string | null,
  ) {}

  private fetch(path: string, init: RequestInit = {}): Promise<Response> {
    const headers = new Headers(init.headers);
    if (this.key) headers.set(EDITOR_KEY_HEADER, this.key);
    return this.fetchImpl(path, { ...init, headers });
  }

  private async getJson(path: string): Promise<unknown> {
    const response = await this.fetch(path);
    if (response.status === 401) throw new Error(EXPIRED_LINK);
    if (!response.ok) throw new Error(`${path}: HTTP ${String(response.status)}`);
    return response.json();
  }

  async config(): Promise<Config> {
    const body = await this.getJson("/api/config");
    if (!isConfig(body)) throw new Error("/api/config: unexpected response");
    return body;
  }

  /** Problems with config.json on disk; empty when the file is fine. */
  async diskErrors(): Promise<Issue[]> {
    const body = await this.getJson("/api/config/status");
    return isRecord(body) && isArrayOf(body.errors, isIssue) ? body.errors : [];
  }

  async apps(): Promise<InstalledApp[]> {
    const body = await this.getJson("/api/apps");
    return isArrayOf(body, isApp) ? body : [];
  }

  async devices(): Promise<DeviceInfo[]> {
    const body = await this.getJson("/api/devices");
    return isArrayOf(body, isDevice) ? body : [];
  }

  async save(config: Config): Promise<SaveResult> {
    let response: Response;
    try {
      response = await this.fetch("/api/config", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(config),
      });
    } catch {
      return { ok: false, error: "The agent isn't running." };
    }
    if (response.status === 401) return { ok: false, error: EXPIRED_LINK };
    const body: unknown = await response.json().catch(() => null);
    if (response.ok && isConfig(body)) return { ok: true, config: body };
    if (response.status === 422 && isRecord(body) && isArrayOf(body.errors, isIssue)) {
      return { ok: false, issues: body.errors };
    }
    return { ok: false, error: `Save failed (HTTP ${String(response.status)}).` };
  }

  async revoke(deviceId: string): Promise<boolean> {
    const response = await this.fetch(`/api/devices/${encodeURIComponent(deviceId)}`, {
      method: "DELETE",
    });
    return response.ok || response.status === 404;
  }
}
