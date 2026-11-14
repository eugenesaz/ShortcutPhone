# Changelog

## [0.2.0] - 2026-11-14

- Automatic updates: the app checks for a new version once a day and installs it with one
  click. **Check for Updates…** is in the menu, next to the version number. Install this
  version by hand once; later versions arrive by themselves.

## [0.1.1] - 2026-11-14

- Security: icon requests are rounded up to a few fixed sizes. Before, anyone on the network
  could make the app render and keep every size from 16 to 512 of every installed app's icon,
  using up memory.
- Text and key taps from several phones at once now run one after another. Before, two
  simultaneous text taps could leave the wrong text on your clipboard.

## [0.1.0] - 2026-11-14

First public release.

- Menu-bar agent for macOS 14+ that serves a touch UI to a paired phone over Wi-Fi, or over
  USB with `adb reverse`.
- Button types: open app, text (paste + Return, clipboard restored), key combo, and web page.
- Pages per app that follow the frontmost app, plus an always-visible app strip.
- Grid that never scrolls, with per-page capacity enforced by the editor and the agent.
- Browser editor with an app picker, capacity counters and device revocation.
- QR pairing with one-time codes, and hashed device tokens.
- Starter config installed on first launch.
