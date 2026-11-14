// Visual feedback for presses: a brief green/red flash on the tile, and a toast for errors.

const FLASH_MS = 400;
const TOAST_MS = 2000;

export function flashTile(root: HTMLElement, buttonId: string, ok: boolean): void {
  const tile = [...root.querySelectorAll<HTMLElement>(".tile")].find(
    (el) => el.dataset.buttonId === buttonId,
  );
  if (!tile) return;
  const cls = ok ? "tile--ok" : "tile--error";
  tile.classList.remove("tile--ok", "tile--error");
  tile.classList.add(cls);
  setTimeout(() => {
    tile.classList.remove(cls);
  }, FLASH_MS);
}

let toastTimer: ReturnType<typeof setTimeout> | undefined;

export function showToast(root: HTMLElement, message: string): void {
  root.querySelector(".toast")?.remove();
  clearTimeout(toastTimer);
  const toast = document.createElement("div");
  toast.className = "toast";
  toast.setAttribute("role", "status");
  toast.textContent = message;
  root.append(toast);
  toastTimer = setTimeout(() => {
    toast.remove();
  }, TOAST_MS);
}
