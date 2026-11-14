// Mirrors KeyCombo.parse in Sources/ShortcutPhoneCore/KeyCombo.swift; both are checked
// against Tests/Fixtures/keycombos.json. Only validity matters on the web side.

const MODIFIERS = new Set([
  "cmd",
  "command",
  "⌘",
  "shift",
  "⇧",
  "alt",
  "opt",
  "option",
  "⌥",
  "ctrl",
  "control",
  "⌃",
]);

const NAMED_KEYS = new Set([
  "space",
  "return",
  "enter",
  "tab",
  "esc",
  "escape",
  "delete",
  "backspace",
  "up",
  "down",
  "left",
  "right",
]);

const PUNCTUATION = new Set(["-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`"]);

function isKey(name: string): boolean {
  if (NAMED_KEYS.has(name)) return true;
  if (name.length === 1) return /^[a-z0-9]$/.test(name) || PUNCTUATION.has(name);
  const fn = /^f([0-9]+)$/.exec(name);
  if (!fn?.[1]) return false;
  const number = Number(fn[1]);
  return number >= 1 && number <= 20;
}

/** Whether `text` is a combo like `cmd+shift+p`, `1`, `f5` or `space`. */
export function isKeyCombo(text: string): boolean {
  const parts = text
    .toLowerCase()
    .split("+")
    .map((part) => part.replace(/^[ \t]+|[ \t]+$/g, ""));
  const last = parts[parts.length - 1];
  if (last === undefined || parts.some((part) => part === "")) return false;
  return parts.slice(0, -1).every((part) => MODIFIERS.has(part)) && isKey(last);
}
