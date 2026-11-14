# Contributing

Thanks for helping! Bug reports, ideas and pull requests are all welcome. For a big change,
open an issue first so we can agree on the approach.

## Setup

You need Xcode 26 or later (Swift 6.2+) and Node 22. See [Building from source](README.md#building-from-source).

```sh
npm --prefix web ci
./scripts/make-signing-identity.sh   # once
./scripts/check.sh                   # every gate CI runs
```

`./scripts/swift-test.sh --filter <name>` runs some of the Swift tests.

For the web UI, `npm --prefix web run dev` starts Vite with `/api`, `/ws` and `/icons` proxied
to a running agent on port 8765. The editor API needs the per-launch key: open the editor from
the menu once and copy `#key=…` from the address bar onto the Vite editor URL.

## Layout

```
Sources/
  ShortcutPhoneCore/    config model and validation, protocol, pairing, capacity math, press
                        dispatch. Pure Swift, no AppKit; OS access goes through small protocols
  ShortcutPhoneMac/     the real OS adapters: NSWorkspace, CGEvent, pasteboard, icons, adb
  ShortcutPhoneServer/  Hummingbird HTTP + WebSocket server, auth and loopback guards
  ShortcutPhoneApp/     the menu-bar app that wires everything together
Tests/                  Swift Testing; Fixtures/ is shared with the web tests
web/src/phone/          the phone UI
web/src/editor/         the editor
web/src/shared/         protocol and config types, shared with the Swift side through fixtures
```

[SPEC.md](SPEC.md) is the design: behavior, protocol, security model and decisions. If a
change alters behavior, update the spec in the same PR.

## Conventions

- **Tests first** for Core and Server logic. Tests never send real keystrokes or touch the real
  pasteboard; use the fakes in the test support files.
- **Swift and TypeScript share fixtures** in `Tests/Fixtures` (protocol messages, configs,
  capacity cases, key combos). Change both sides together.
- **Formatting:** `swift format` (`.swift-format`, 100 columns) and Prettier + ESLint for the
  web. `./scripts/check.sh` checks all of them.
- **No SwiftUI macros** (`@State`, `@Entry`, `#Preview`), so the app still builds with the
  Command Line Tools alone. `@Observable` is fine.
- Core line coverage must stay at 85% or more (`check.sh` enforces it).

Hardware behavior that tests can't cover (Accessibility, real keystrokes, the phone) is in
[docs/manual-test.md](docs/manual-test.md). Run the relevant rows when you touch that code.

## Releases

See [docs/releasing.md](docs/releasing.md).
