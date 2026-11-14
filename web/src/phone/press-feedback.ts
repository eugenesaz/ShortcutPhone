// Visual feedback for presses: a brief green/red flash on the tile, and a toast for errors.

const FLASH_MS = 400;
const TOAST_MS = 2000;

/**
 * Flashes the first tile on screen for one of `ids`: a button's id, or the id of the folder
 * holding it (after the folder has closed). Returns whether a tile was found.
 */
export function flashTile(root: HTMLElement, ids: string | string[], ok: boolean): boolean {
  const tiles = [...root.querySelectorAll<HTMLElement>(".tile")];
  let tile: HTMLElement | undefined;
  for (const id of typeof ids === "string" ? [ids] : ids) {
    tile = tiles.find((el) => el.dataset.buttonId === id || el.dataset.folderId === id);
    if (tile) break;
  }
  if (!tile) return false;
  const cls = ok ? "tile--ok" : "tile--error";
  tile.classList.remove("tile--ok", "tile--error");
  tile.classList.add(cls);
  setTimeout(() => {
    tile.classList.remove(cls);
  }, FLASH_MS);
  return true;
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
