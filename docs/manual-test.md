# Manual test checklist

Real OS behavior that automated tests can't cover: Accessibility, real keystrokes, the phone.
Run the rows that touch your change, and the whole list before a release. Copy the tables into
the PR or release notes and fill in the results.

## Setup

1. `./scripts/make-signing-identity.sh` (once). macOS asks for your login password to trust the
   certificate for code signing.
2. `./scripts/bundle.sh && open build/ShortcutPhone.app`. A phone icon appears in the menu bar,
   and the menu shows `Wi-Fi: http://<mac-ip>:8765`.
3. With no `~/Library/Application Support/ShortcutPhone/config.json` yet, the first launch
   installs `Resources/starter-config.json`: pages for **Notes** (text buttons and a key combo)
   and **Terminal** (2 columns), plus Safari/Notes/Terminal/TextEdit in the app strip. To start
   over, quit the app and move that folder away.
4. Menu → **Accessibility: not granted — Open Settings…**, then switch ShortcutPhone on. Within
   2 s the menu changes to "Accessibility: granted". If the switch is on but the menu still
   says "not granted", the entry belongs to an older signature: quit the app, run
   `tccutil reset Accessibility io.github.eugenesaz.shortcutphone`, reopen and grant again.
5. **Connection.** Wi-Fi: the phone opens the menu's Wi-Fi URL. If it can't, run
   `route -n get <phone-ip>`. A `utun` interface means a VPN is routing local traffic into its
   tunnel, so use USB instead (Android):
   - `brew install --cask android-platform-tools`
   - On the phone: Settings → About phone → tap **Build number** 7 times, then Developer
     options → **USB debugging** on.
   - Plug in the phone and accept "Allow USB debugging?". Within 5 s the menu shows
     `USB: <phone> — http://localhost:8765`.
   - **Pair Phone…** → **USB** tab, then scan the QR.

## Install and first run

| # | Check | How | Result |
|---|---|---|---|
| R1 | Release zip opens | Download the release zip on a Mac that never ran ShortcutPhone. Unzip, move to Applications, open: blocked. **Privacy & Security › Open Anyway**: it starts, and the menu-bar icon appears | |
| R2 | Starter config | On that first run, the phone shows the starter strip, and the Notes page while Notes is in front | |
| R3 | Accessibility survives an update | Grant Accessibility on version N, then replace the app with N+1 (same release identity): the menu still says "granted" | |
| R5 | Automatic update | With version N installed in `~/Applications`, publish N+1. **Check for Updates…** offers it with its notes; **Install** relaunches into N+1, and the menu still says "Accessibility: granted" | |
| R4 | Local signature | `codesign -dvvv build/ShortcutPhone.app 2>&1 \| grep Authority` shows `ShortcutPhone Local`. Rebuild twice: the menu still says "granted" | |

## Pairing and auth

| # | Check | How | Result |
|---|---|---|---|
| P1 | Pair by QR | Menu → **Pair Phone…**. Scan the QR with the phone's camera and open it in Chrome. The page shows the buttons, and "Not paired" never appears | |
| P2 | Unpaired device refused | Open the phone URL on another device, or in an incognito tab. It shows "Not paired" and no buttons | |
| P3 | Editor refused from the LAN | On the phone over Wi-Fi, open `http://<mac-ip>:8765/editor`: 403, no editor | |
| P4 | Editor key over USB | On a USB-connected phone, open `http://localhost:8765/api/config`: 401, and no config is shown | |
| P5 | Expired editor link | Open the editor, quit and reopen the app, then reload the editor: "This editor link has expired…". **Open Editor…** from the menu works again | |
| P6 | Survives restarts | Quit and reopen the app: the phone reconnects within 5 s without re-pairing. Reboot the phone: still paired | |
| P7 | Revoke | Editor → **Paired phones** → **Revoke** a connected phone: it shows "Not paired" at once. Pair it again | |

## Actions

| # | Check | How | Result |
|---|---|---|---|
| A1 | Follows focus | Switch Mac apps: Notes shows its page, Terminal its 2-column page, Finder the large app grid. It feels instant | |
| A2 | Launch or switch | Quit Safari and tap Safari: it launches. Hide it (⌘H) and tap: it comes back. Close all its windows and tap: a window reappears | |
| A3 | Text + Return | Copy an image first. In a Notes note, tap **Hello** and **Thanks**: the exact text plus a new line each time. Then ⌘V elsewhere: the image comes back | |
| A4 | Text in Electron apps | Add a page for Slack or VS Code with a text button. The text arrives *before* Return, so no empty message is sent | |
| A5 | Key combo | In Notes, tap **New note** (`cmd+n`): a new note appears. In Terminal, **Clear** (`cmd+k`) clears | |
| A6 | Fullscreen key | Make TextEdit fullscreen (⌃⌘F) with a page button that sends `1`. Tap: `1` appears | |
| A7 | Focus guard | Open Notes, then quickly switch to Finder and tap a Notes text button before the phone updates. Nothing is typed, and the tile flashes red | |
| A8 | No Accessibility | Switch ShortcutPhone off in Accessibility settings. A text tap gives a red flash and the toast "Allow ShortcutPhone in Accessibility settings…". Switch it back on | |
| A9 | Web page buttons | Add an **Open web page** button to a Microsoft Edge page and to a Google Chrome page. Each opens a new tab in its own browser. `example.com` without `https://` is refused in the editor | |

## Connection

| # | Check | How | Result |
|---|---|---|---|
| N1 | Reconnect | Quit the app: the phone shows "Disconnected" and a red dot. Reopen: green within 5 s | |
| N2 | USB replug | Unplug the cable: "Disconnected". Plug it back in: green within about 10 s | |
| N3 | Mac sleep | Sleep the Mac and wake it: the phone's dot is green within 5 s | |
| N4 | Phone count | The menu shows "1 phone connected". Close the phone tab: "No phones connected" within a few seconds | |

## Grid and capacity

| # | Check | How | Result |
|---|---|---|---|
| G1 | No scroll | Give a page 1, 4, 12 and 24 buttons. In portrait **and** landscape: square tiles, all visible, nothing scrolls when you drag | |
| G2 | Densest page | Fill a page until **Add button** turns off. Both orientations: tiles ≥ 56 px, no scroll, and emoji tiles drop their labels | |
| G3 | `columns` override | Set **Columns** to 2 on a page with 6 buttons: 2 columns. A value marked too small for the button count is refused | |
| G4 | Live reload | Change a label in `config.json` by hand: the phone updates within about 1 s. Break the JSON: the menu shows the error and the phone keeps the old buttons. Fix it: the error clears | |
| G5 | Strip scrolls | Add 10+ apps to the strip. On the phone it scrolls sideways (up and down in landscape), pinned apps come first, and tapping an app jumps the strip back to the start | |

## Editor

| # | Check | How | Result |
|---|---|---|---|
| E1 | Opens from the menu | **Open Editor…** shows the app strip, the pages with app icons, "N / max" counters, and **Paired phones** | |
| E2 | Build a page | **App pages** → pick an app → **Add page**. Add a text, a keys and an app button. **Save**: the phone shows the page within about 1 s while that app is in front | |
| E3 | Edit, reorder, delete | Change a tile's label and color, move it with ← / →, delete it, and reorder and delete pages. Save after each: the phone follows. **Discard changes** restores the last save | |
| E4 | Inline errors | Clear a text button's text, or type `cmd+nope` as keys: red text under the field, a red tile, and Save turns off | |
| E5 | Broken file | Break `config.json` by hand and reload the editor: a red "config.json on disk is invalid" banner and the last good config. Save fixes the file and the banner goes away | |

## Menu and home screen

| # | Check | How | Result |
|---|---|---|---|
| M1 | Launch at Login | Menu → **Launch at Login**. Log out and back in: the menu-bar icon is there | |
| M2 | Home screen app (USB) | In Chrome at `http://localhost:8765`: ⋮ → **Add to home screen** → **Install**. It opens full screen, with no address bar, and stays paired | |
| M3 | Latency | Run the command below and switch apps or tap about 20 times: `focus→state` p95 ≤ 300 ms, `press→action` p95 ≤ 150 ms | |

```sh
log stream --level debug --predicate 'subsystem == "io.github.eugenesaz.shortcutphone"'
```

Over Wi-Fi the page is plain `http://<ip>`, which Chrome doesn't treat as secure, so **Add to
home screen** only adds a bookmark-style shortcut that opens in a tab. Over USB it's
`http://localhost`, which counts as secure, so M2 installs a real full-screen app.
