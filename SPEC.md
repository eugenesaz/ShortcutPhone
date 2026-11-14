# Spec: ShortcutPhone

_Status: v1 built, 2026-11-14._

## Objective

Turn an idle **Pixel 5** on the desk into a Stream Deck–style touch panel for **this Mac**.
A Swift menu-bar app on the Mac (the **agent**) serves a touch web UI over the local Wi-Fi.
The phone opens it in Chrome, pinned to the home screen. Tapping a button runs an action on the Mac.

**User:** one person (the owner), using one Mac and one phone on the same home network.

**Primary use cases**
- **T3 Code and AI agents:** text buttons that paste frequent prompts or replies into the agent chat and send them. Pages have a few to a dozen buttons.
- **World of Warcraft:** many keybind buttons on one page (abilities, macros bound to keys), plus some text buttons (chat or slash commands). Pages may have 20–40 buttons.

### User stories

1. **Launch or switch.** I tap an app button. If the app is not running, it launches. If it is running, it comes to the foreground.
2. **Follow focus.** When I switch apps on the Mac, the phone shows that app's shortcut page automatically.
3. **Text shortcut.** On an app's page, I tap a text button. The Mac types the predefined text into the focused app and presses Enter.
4. **Key combo.** I tap a combo button such as `⌘⇧P` and the Mac sends that keystroke.
5. **Global page.** A strip of app-launch buttons is always visible, whatever app is focused.
6. **Look.** Buttons show the macOS app icon, or a custom color, label and emoji.
7. **Configure.** I set up apps, pages and buttons in a web editor in the Mac's browser. The phone updates live when I save.
8. **Pair.** The phone has to be paired once by scanning a QR code from the menu-bar app. Other devices on the Wi-Fi can't trigger actions.

### Out of scope for v1

- Windows/Linux, iOS, and native phone apps
- Text shortcuts **without** Enter (Enter is always pressed)
- Typing via simulated keystrokes (paste only)
- Multi-step macros, scripts, shell commands, media/volume controls
- Multiple Macs, multiple users, and remote access outside the LAN
- HTTPS/TLS. Plain HTTP on the home LAN is accepted for v1 (decided 2026-11-13). The pairing token stops other devices from triggering actions, but it does not hide traffic from someone sniffing the Wi-Fi.

## Behavior

### Actions

| Action | Config `type` | Behavior on the Mac |
|---|---|---|
| Launch or switch | `app` | `NSWorkspace.openApplication(at:configuration:)` with `activates = true`. This launches the app if it isn't running. If it is running, it activates the app and sends a reopen event, which restores a window if none are visible. Apps are identified by **bundle ID**. |
| Text | `text` | 1. Save the current pasteboard (all items and types). 2. Write the text as a plain string. 3. Post `⌘V`. 4. Post `Return`. 5. Restore the saved pasteboard after about 300 ms. |
| Web page | `url` | Open `url` (`http`/`https` only) in the **page's app** with `NSWorkspace.open(_:withApplicationAt:configuration:)`, which opens a new tab and brings the browser to the front. So `url` buttons on the Microsoft Edge page (`com.microsoft.edgemac`) open in Edge, and on the Chrome page (`com.google.Chrome`) in Chrome. Page buttons only. Nothing is typed, and no Accessibility permission is needed. |
| Key combo | `keys` | Post a CGEvent key-down/up with the modifiers, e.g. `"cmd+shift+p"`. A single key with no modifiers is also valid (`"1"`, `"f5"`, `"space"`, `"esc"`), as needed for game keybinds. Supported: letters, digits, F1–F20, arrows, space, return, tab, esc, delete, and punctuation, plus the `cmd`/`shift`/`alt`/`ctrl` modifiers. |

**Focus guard:** `text` and `keys` buttons belong to an app page. They run only if that page's app is **still frontmost** when the press arrives. If it isn't, the agent rejects the press with `wrong_app` and the phone shows a brief error. This keeps text from landing in the wrong app because of a race. Text and key presses run **one at a time**, in arrival order, whichever phone sent them (each paste saves and restores the clipboard, so overlapping pastes would lose it). The focus guard is checked when a queued press's turn comes. `app` and `url` buttons have no guard, even on a page.

### Phone UI (`/`)

- Layout in portrait and landscape:
  - **Global strip**: one row (portrait) or one column (landscape) of `app` buttons, with no limit on how many. When they don't all fit, the strip scrolls sideways (portrait) or up and down (landscape). It is the only part of the phone UI that scrolls.
    - **Pinned** apps (`"pinned": true`) come first; the rest follow in editor order. Pinned apps scroll with the others and don't stay fixed on screen.
    - Tapping an app in the strip scrolls it back to the start, and so does every update from the agent.
  - **Page area**: a grid with the frontmost app's buttons.
- If the frontmost app has no page, the page area shows a large grid of the global apps.
- **Dynamic grid.** The page area sizes itself to the number of buttons:
  - It picks the column and row count that makes square-ish buttons as large as possible while all of them still fit in the visible page area. 1–4 buttons get big tiles; 30+ buttons get a dense grid.
  - **The UI never scrolls.** All buttons always fit on one screen.
  - Buttons never shrink below a **minimum tap size of 56 CSS px** (about 9 mm), with 8 px gaps.
  - That limits how many buttons a page can have. The limit is called **capacity** and is enforced by the editor and the agent (see "Capacity" below). The phone never has to fit more than it can show.
  - A page can set an optional `columns` override (1–8) in the config. Rows then follow from the button count.
  - The grid recalculates on rotation and resize.
  - Defensive fallback: if a page arrives with more buttons than currently fit (for example a smaller phone paired later), the phone fills the grid at the minimum size and makes the last tile a red **"+N hidden — edit page"** tile. It still doesn't scroll.
  - Labels shrink to fit, down to a minimum size, then truncate with an ellipsis. On dense grids, the emoji or icon takes priority and the label is dropped.
  - Buttons keep the order set in the editor, filling row by row.
- The header shows the frontmost app's name and icon, plus a connection dot.
- Uses one WebSocket to the agent. It reconnects automatically with backoff (max 5 s) and shows "Disconnected" while offline.
- Every press gets haptic feedback (`navigator.vibrate`) and a visual flash: green for OK, red for an error.
- Runs as a home-screen web app with a manifest and `display: standalone`. The screen stays on through Android's "Stay awake while charging" setting, because the Wake Lock API needs HTTPS.

### Editor (`/editor`)

- Served only to **loopback** clients (`127.0.0.1` / `::1`). Opened from the menu-bar item "Open Editor…".
- Lets you add, edit, delete and reorder:
  - global app buttons
  - app pages, with an app picker that lists installed apps and running apps
  - buttons inside a page
- Each button has a label, an optional emoji, an optional color, and an icon (defaults to the target app's icon for `app` buttons, and to the page app's icon for `url` buttons; a `url` button without a label shows the site's host name).
- **Capacity is enforced while editing.**
  - Each page shows a "N / max buttons" counter.
  - Once a page is at capacity, **Add button is disabled**, with a hint: remove a button, or change `columns`.
  - The global strip has no limit (it scrolls). Its counter shows how many apps fit without scrolling on the smallest paired phone. Each global app has a **Pin to the front** toggle; pinned apps stay grouped at the start of the strip, and reordering keeps them there.
  - Lowering `columns`, or any other change that would push a page over capacity, is blocked with an inline error.
- **Save** validates and writes the config, including the capacity check. The agent then pushes the new state to connected phones.

### Capacity

- When the phone connects, and again whenever it resizes, it reports the page-area size and global-strip size for **both orientations** (`viewport` message).
  - It measures the orientation it is in. For the other one it uses its last measurement (kept in `localStorage`), or an estimate from the CSS layout until it has been rotated once. The agent ignores sizes outside 0–10 000 px.
- The agent stores the last reported sizes for each paired device in `devices.json`.
- **Effective capacity** is the smallest value across all paired devices and both orientations.
  - Page capacity: `cols × rows`, with `cols = floor((w + 8) / (56 + 8))` and `rows = floor((h + 8) / (56 + 8))`. With a `columns` override `c`, it is `c × rows`, but only if `(w − 8(c − 1)) / c ≥ 56`. Otherwise the override is invalid.
  - Strip capacity: one row (portrait) or one column (landscape), whichever holds fewer buttons. It is informational only (how many fit without scrolling); it is not enforced.
- If no device has reported a size yet, the agent uses a built-in **Pixel 5 profile** (393×851 CSS px). That gives roughly 6×11 = 66 per page in portrait and about 11×5 = 55 in landscape, so the effective page capacity is about 55. About 6 strip apps fit without scrolling.
- `PUT /api/config` rejects any page over capacity with a field-level error. The editor's checks are for convenience; this server check is the one that counts.
- The capacity math lives in `Core` (Swift) and `web/src/shared` (TS). Shared fixtures keep the two in sync.
- Lists paired devices with a **Revoke** button for each.

### Menu-bar app

- The menu shows:
  - Status: Wi-Fi URL, USB status (when `adb` is installed), number of connected phones, and Accessibility permission (granted, or not granted with an "Open Settings" item)
  - **Pair Phone…**: a window with a QR code and the URL, with a Wi-Fi / USB switch
  - **Open Editor…**
  - **Launch at Login** toggle (`SMAppService`)
  - **Quit**
- No Dock icon (`LSUIElement`).

### Pairing and auth

1. **Pair Phone…** creates a one-time code (random, 128 bits) that expires after 5 minutes. The QR code encodes `http://<mac-lan-ip>:<port>/pair?code=<code>`.
2. The phone redeems the code at `POST /api/pair` and receives a long-lived device token (random, 256 bits). The token goes into `localStorage`.
3. Every phone HTTP/WS request must carry the token: `Authorization: Bearer` for HTTP, or the first WS message for the socket. Requests without a valid token get `401` or the socket is closed with code `4401`.
4. The agent stores tokens only as SHA-256 hashes, in `devices.json`. Revoking a device deletes its hash and closes its socket.
5. Editor endpoints accept loopback connections only and need no device token. They also
   require a loopback `Host` header, and a loopback `Origin` if one is sent, to block DNS
   rebinding and cross-site requests. Paths are percent-decoded, lowercased and dot-resolved
   before matching, so variants like `/%65ditor.html` are caught. The editor API (`/api/config`,
   `/api/apps`, `/api/devices`) also needs the **editor key**: a random 256-bit secret made at
   each launch. **Open Editor…** opens `/editor#key=<key>`, and the editor sends it as
   `X-ShortcutPhone-Editor-Key` on every call; a missing or wrong key gets `401`. The fragment
   never reaches the server. The editor keeps the key in `sessionStorage` for reloads and
   removes it from the address bar. After the agent restarts, the editor must be reopened from
   the menu. The `/editor` page itself is static and needs no key.
6. Static files (`/`, `/pair`, assets) and `/icons/*` are public, because a page load or an
   `<img>` can't carry a bearer token. Every other phone `/api/*` route needs the token.
7. **USB connection (adb).** When `adb` is installed, the agent runs
   `adb reverse tcp:<port> tcp:<port>` for every authorized phone every 5 s, so the phone
   reaches it at `http://localhost:<port>` over the cable. The pairing QR then encodes
   `http://localhost:<port>/pair?code=<code>`. A USB phone's requests arrive from loopback with
   a `localhost` Host, so they pass the loopback checks in item 5. That's why the editor API
   also needs the editor key: without it, any app on a USB phone could rewrite buttons (for
   example a `text` button that pastes into Terminal). Phone actions still need the device
   token.

### Interfaces

**HTTP**
- `GET /`: phone UI (static)
- `GET /editor`: editor UI (static; loopback only)
- `GET /icons/<bundleId>.png?size=128`: app icon, rendered from `NSWorkspace.icon(forFile:)` and cached. Sizes are rounded up to 64, 128, 256 or 512 (larger requests get 512), so this public route can't fill the cache with every size
- `POST /api/pair` `{code}` → `{token, deviceId}`
- `GET /api/config`, `PUT /api/config`: loopback + editor key
- `GET /api/config/status` → `{errors?: [{path, message}]}`: problems with `config.json` on disk, if any (the last good config stays active). Loopback + editor key.
- `GET /api/apps`: installed and running apps (bundle ID, name, path). Loopback + editor key.
- `GET /api/devices` → `[{id, name, pairedAt, viewport?, connected}]` (never the token hash), `DELETE /api/devices/<id>` → 204, or 404 if unknown: loopback + editor key

**WebSocket `/ws`**: JSON messages, each with a `type` field.

```jsonc
// phone → agent
{ "type": "auth", "token": "…" }
{ "type": "press", "pressId": "uuid", "buttonId": "btn_42" }
{ "type": "viewport",
  "portrait":  { "page": { "w": 393, "h": 700 }, "strip": { "w": 393, "h": 72 } },
  "landscape": { "page": { "w": 700, "h": 345 }, "strip": { "w": 72, "h": 393 } } }

// agent → phone
{ "type": "state", "frontmost": { "bundleId": "com.apple.Safari", "name": "Safari" },
  "global": [Button], "page": Page | null }
{ "type": "result", "pressId": "uuid", "ok": true }
{ "type": "result", "pressId": "uuid", "ok": false, "error": "wrong_app" | "no_accessibility" | "launch_failed" | "unknown_button" }
```

App buttons without a `label` get the app's display name as their `label` in `state` (the phone has no app list of its own). The agent sends `state` in four cases: after auth succeeds, when the frontmost app changes (`NSWorkspace.didActivateApplicationNotification`), when the config is saved, and when the config file changes on disk.

### Config

The config lives at `~/Library/Application Support/ShortcutPhone/config.json`. It is versioned and validated on load. If the file is invalid, the agent keeps the last good config and shows the error in the menu and the editor.

```json
{
  "version": 1,
  "server": { "port": 8765 },
  "global": [
    { "id": "btn_1", "type": "app", "bundleId": "com.apple.Safari", "pinned": true },
    { "id": "btn_2", "type": "app", "bundleId": "com.tinyspeck.slackmacgap", "color": "#4A154B" }
  ],
  "pages": [
    {
      "bundleId": "com.tinyspeck.slackmacgap",
      "columns": null,
      "buttons": [
        { "id": "btn_3", "type": "text", "label": "LGTM", "emoji": "👍", "text": "LGTM, merging." },
        { "id": "btn_4", "type": "keys", "label": "Jump to", "keys": "cmd+k" }
      ]
    }
  ]
}
```

## Tech Stack

- **Agent:** Swift 6 (strict concurrency), macOS 14+, built with SwiftPM.
  - Menu bar: SwiftUI `MenuBarExtra`
  - HTTP and WebSocket: `hummingbird` 2.x and `hummingbird-websocket` 2.x
  - QR codes: CoreImage `CIQRCodeGenerator` (no dependency)
- **Web (phone and editor):** TypeScript 5 (strict) and Vite 6 as a multi-page build, with no UI framework. Phone target: Chrome on Android 14 (Pixel 5), with an ES2020 build target. The built files are copied into the app bundle's `Resources/web`.
- **Tooling:** npm, Vitest, ESLint and Prettier for web. `swift-format` for Swift.

## Commands

```bash
# Web
npm --prefix web ci
npm --prefix web run dev          # Vite dev server; proxies /api, /ws, /icons to the agent on :8765
npm --prefix web run build        # → web/dist
npm --prefix web test             # Vitest, single run
npm --prefix web run lint         # eslint + prettier --check
npm --prefix web run typecheck    # tsc --noEmit

# Agent
swift build                       # debug build
swift test                        # unit + server integration tests
swift format lint -r Sources Tests

# App bundle (web build + release build + .app + codesign)
./scripts/make-signing-identity.sh   # one-time: self-signed "ShortcutPhone Local" identity in login keychain
./scripts/bundle.sh               # → build/ShortcutPhone.app, signed with "ShortcutPhone Local" (override: CODESIGN_IDENTITY)
open build/ShortcutPhone.app

# Everything CI-style
./scripts/check.sh                # web lint/typecheck/test/build + swift format lint + swift test
```

## Project Structure

```
Package.swift
Sources/
  ShortcutPhoneCore/     → Pure logic, no AppKit: config model + validation, button lookup,
                           focus guard, press dispatch, pairing/token logic, protocol messages
  ShortcutPhoneMac/      → OS adapters behind Core protocols: AppLauncher (NSWorkspace),
                           FrontmostAppMonitor, Pasteboard, KeyInjector (CGEvent), IconRenderer,
                           AccessibilityStatus, InstalledApps
  ShortcutPhoneServer/   → Hummingbird routes, WebSocket hub, auth middleware, loopback guard,
                           static file serving
  ShortcutPhoneApp/      → @main menu-bar app: wiring, MenuBarExtra, pairing window
Tests/
  ShortcutPhoneCoreTests/
  ShortcutPhoneServerTests/  → in-process server tests with fake adapters
web/
  package.json  vite.config.ts  tsconfig.json
  index.html  editor.html
  src/shared/   → protocol types, WS client w/ reconnect, config types
  src/phone/    → phone UI
  src/editor/   → editor UI
  tests/        → Vitest (jsdom)
Resources/      → Info.plist, app icon, starter-config.json (installed on first launch)
scripts/        → make-signing-identity.sh, bundle.sh, check.sh, release scripts
docs/           → manual-test.md
SPEC.md
```

**Dependency rule:** `Core` imports nothing app-specific. `Mac` and `Server` depend on `Core`. `App` wires everything together. The protocol types in `Core` and `web/src/shared` must stay in sync, and a shared JSON fixture test checks this.

## Code Style

**Swift.** OS access goes through small protocols, so the logic can be tested with fakes. The code uses `async`/`await` and actors, and each case has its own error enum. There are no force-unwraps outside tests.

```swift
public protocol AppLauncher: Sendable {
    func launchOrActivate(bundleId: String) async throws(ActionError)
}

public enum ActionError: Error, Equatable, Sendable {
    case wrongApp(expected: String, actual: String?)
    case noAccessibility
    case launchFailed(bundleId: String)
    case unknownButton(id: String)
}

public actor PressDispatcher {
    private let launcher: any AppLauncher
    private let typer: any TextTyper
    private let frontmost: any FrontmostAppProvider

    public func handle(_ press: Press, config: Config) async throws(ActionError) {
        guard let (button, owner) = config.lookup(press.buttonId) else {
            throw .unknownButton(id: press.buttonId)
        }
        if case .page(let bundleId) = owner, await frontmost.bundleId != bundleId {
            throw .wrongApp(expected: bundleId, actual: await frontmost.bundleId)
        }
        switch button.action {
        case .app(let id):   try await launcher.launchOrActivate(bundleId: id)
        case .text(let t):   try await typer.pasteAndReturn(t)
        case .keys(let k):   try await typer.send(k)
        }
    }
}
```

- Types use `UpperCamelCase`. Members use `lowerCamelCase`. One primary type per file, and the file is named after it.

**TypeScript.** Strict mode with no `any`. Inbound messages use discriminated unions and are parsed at the boundary. The DOM is updated through small render functions.

```ts
export type ServerMsg =
  | { type: "state"; frontmost: AppRef | null; global: Button[]; page: Page | null }
  | { type: "result"; pressId: string; ok: true }
  | { type: "result"; pressId: string; ok: false; error: PressError };

export function parseServerMsg(raw: string): ServerMsg | null {
  const msg: unknown = JSON.parse(raw);
  return isServerMsg(msg) ? msg : null; // never trust the wire
}
```

- Files are named in `kebab-case.ts`. Named exports only. Prettier defaults with `printWidth: 100`.

## Testing Strategy

| Level | What | Tool | Where |
|---|---|---|---|
| Unit | Config decode/validate/migrate, capacity math + over-capacity rejection, button lookup, focus guard, dispatch with fake adapters, pairing code expiry, token hashing, key-combo parsing | Swift Testing | `Tests/ShortcutPhoneCoreTests` |
| Integration | Real Hummingbird server in-process with fake adapters: auth (401 / 4401), loopback-only editor routes, pair flow, WS state push on frontmost change and config save, press → result | Swift Testing + HummingbirdTesting | `Tests/ShortcutPhoneServerTests` |
| Unit | Message parsing, WS reconnect/backoff, phone render (layout, no-page fallback), the grid-fit function (pure: button count + viewport + override → columns, rows, tile size, overflow count), capacity math, editor capacity blocking (Add disabled at max, columns change rejected), editor form validation | Vitest + jsdom | `web/tests` |
| Contract | Shared JSON fixtures of every protocol message, parsed by both Swift and TS tests | both | `Tests/Fixtures/protocol/*.json` |
| Manual | Real OS behavior: launch/switch/reopen, paste + Enter in several apps (Notes, Slack, Terminal, VS Code), clipboard restore, key combos, Accessibility prompt, Pixel 5 layout, reconnect after Mac sleep | checklist | `docs/manual-test.md` |

- TDD for `Core` and `Server` (red, then green, then refactor).
- Coverage target: at least 85% line coverage for `ShortcutPhoneCore`. OS adapter code is kept thin and checked by the manual list.
- No test ever posts real keystrokes or touches the real pasteboard.

## Boundaries

**Always**
- Run `./scripts/check.sh` before every commit.
- Put every OS side effect behind a `Core` protocol, and test logic with fakes.
- Validate every inbound message and config at the boundary.
- Enforce auth on every phone route and loopback on every editor route.
- Restore the user's clipboard after a paste.
- Keep the phone UI scroll-free: enforce capacity on the server, never allow a scrolling page area, and never shrink tiles below 56 px.
- Keep Swift and TS protocol types in sync, and update the fixtures when either one changes.
- Update this spec first when behavior or scope changes.

**Ask first**
- Adding any dependency beyond the stack listed above (Swift or npm)
- Changing the wire protocol, the config schema version, or the default port
- Adding new action types or features listed under Out of scope
- Changing the minimum macOS or phone browser target
- Anything that widens the network surface: binding beyond the LAN, Bonjour, CORS, TLS
- Moving to the next lifecycle phase (`/plan`, `/build`, …)

**Never**
- Accept actions from unauthenticated clients, or serve the editor or config API to non-loopback clients
- Store raw device tokens, or log typed text or tokens
- Execute shell commands or arbitrary scripts from config or wire input
- Commit secrets, signing identities or personal config files
- Skip, delete or weaken failing tests to get to green
- Re-enable the Superpowers plugin for this project

## Success Criteria

1. Tapping a global button for an app that isn't running launches it. Tapping it while the app is running brings it frontmost, including when the app is hidden or has no visible window. Verified manually with Safari, Notes and Slack.
2. After the frontmost app changes on the Mac, the phone shows that app's page (or the fallback) within **300 ms** on home Wi-Fi.
3. A text button types its exact text, including non-ASCII text (Cyrillic, emoji), and then Enter. The previous clipboard contents are restored afterwards.
4. A key combo button produces the configured keystroke in the frontmost app.
5. If the page's app isn't frontmost, a `text` or `keys` press does nothing on the Mac and the phone shows a `wrong_app` error.
6. Over Wi-Fi, a tap starts the action within **150 ms** at p95, measured from WS receipt to the start of the action.
7. Without a valid token, `/api/*` (except `/api/pair`) returns 401 and `/ws` closes with 4401. Editor routes return 403 to non-loopback clients. All three are covered by integration tests.
8. After a phone is paired by QR code, it survives an agent restart and a phone reboot without re-pairing. A revoked phone is disconnected immediately.
9. The phone reconnects within 5 s after the agent restarts or the Mac wakes from sleep.
10. Saving in the editor updates connected phones within 1 s. An invalid config is rejected with a field-level error, and the last good config stays active.
11. Without Accessibility permission, the menu shows the problem, and `text`/`keys` presses return `no_accessibility` instead of failing silently.
12. On the Pixel 5, the phone UI **never scrolls**, in either orientation. Pages with 1, 4, 12, 24 and 55 buttons fill the page area with tiles of at least 56 px. A `columns` override is honored. Covered by grid-fit unit tests and a manual check.
13. Once a page is at capacity, the editor disables Add button. `PUT /api/config` returns a field-level error for any page over capacity, or for a `columns` value that makes tiles smaller than 56 px. Covered by tests.
14. In World of Warcraft (focused, windowed or fullscreen), a single-key button such as `"1"` triggers the action bound to that key.
15. `./scripts/check.sh` passes, and `ShortcutPhoneCore` line coverage is at least 85%.

## Decisions

_Recorded 2026-11-13._

1. **Code signing: local self-signed identity, no Apple Developer certificate.**
   - macOS ties the Accessibility permission to the app's signature. An ad-hoc signature changes on every build, which would re-trigger the permission prompt. A self-signed identity keeps the signature stable across rebuilds, so the permission is granted once.
   - `scripts/make-signing-identity.sh` is a one-time step you run. It creates a self-signed code-signing certificate named `ShortcutPhone Local` in your login keychain.
   - `scripts/bundle.sh` signs with that identity by default. `CODESIGN_IDENTITY` can override it, and `-` falls back to ad-hoc.
   - There is no notarization. The app is for this Mac only.
   - _Update 2026-11-14 (open-source release):_ release builds are signed in CI with a second
     self-signed identity, **ShortcutPhone Release**, kept in the GitHub secrets
     (`docs/releasing.md`). Still no notarization, so users click **Open Anyway** once, but
     every release has the same signature and keeps the Accessibility grant. The bundle ID is
     `io.github.eugenesaz.shortcutphone`.
2. **Mac IP: reserved in the router.** No discovery code is needed. The QR code uses the current LAN IP.
3. **Transport: plain HTTP on the LAN** (see Out of scope).
4. **Grid: dynamic and never scrolls.** Capacity is enforced (see Capacity).
5. **USB via `adb reverse` as well as Wi-Fi** (2026-11-13). Some VPNs route the home LAN into
   their tunnel, so the phone can't reach the Mac over Wi-Fi while they're on. `adb` is a runtime tool found on disk (Homebrew or Android Studio), not a build
   dependency.

6. **Automatic updates with Sparkle 2** (2026-11-14). The app checks
   `releases/latest/download/appcast.xml` daily. Each release's zip is signed with an EdDSA
   key (`SPARKLE_PRIVATE_KEY` secret; the public key is `SUPublicEDKey` in Info.plist) by
   `scripts/sparkle-tool.swift`, which uses CryptoKit rather than Sparkle's prebuilt tools.
   Sparkle's XPC services are left out (they're only for sandboxed apps). The app is signed with
   `com.apple.security.cs.disable-library-validation`, because a self-signed app has no Team ID
   and the hardened runtime would otherwise refuse the embedded framework. Local builds (no
   `VERSION`) turn off automatic checks.

## Deferred / keep in mind

- **World of Warcraft.**
  - Text buttons need chat to be open first, because WoW needs Enter before you can paste. A future option would be a per-button "press Enter before pasting". Not in v1.
  - Synthetic CGEvent keystrokes in WoW are expected to work but are unverified. Success criterion 14 covers this, and it should be spiked early in `/build`. If they fail, raise it then.
  - Keep one keystroke per tap, which complies with Blizzard's rules. No multi-step macros.

## Open Questions

None at the moment.
