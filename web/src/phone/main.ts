import "./phone.css";
import { flashTile, showToast } from "./press-feedback";
import { pageAssets, pageChanged } from "./page-update";
import { contentSize, renderPhone, scrollStripToStart } from "./render";
import { startPhone, type Phone } from "./session";
import { ViewportTracker } from "./viewport";

/** Waits for rotation and the browser's toolbar animation to settle. */
const RESIZE_DEBOUNCE_MS = 200;

const root = document.getElementById("app");

if (root) {
  let phone: Phone | null = null;
  const loadedAssets = pageAssets(document);
  const tracker = new ViewportTracker(localStorage);
  void startPhone({
    storage: localStorage,
    fetch: window.fetch.bind(window),
    location,
    replaceUrl: (path) => {
      history.replaceState(null, "", path);
    },
    render: (model) => {
      renderPhone(root, model);
    },
    feedback: (buttonId, ok, message, folderId) => {
      flashTile(root, folderId === undefined ? buttonId : [buttonId, folderId], ok);
      if (message) showToast(root, message);
    },
    vibrate: (ms) => {
      if ("vibrate" in navigator) navigator.vibrate(ms);
    },
    reconnected: () => {
      // The Mac app may have updated: load its new page so this one doesn't miss new features.
      void pageChanged(window.fetch.bind(window), location.pathname, loadedAssets).then(
        (changed) => {
          if (changed) location.reload();
        },
      );
    },
    viewport: () => {
      const page = root.querySelector<HTMLElement>(".page");
      const strip = root.querySelector<HTMLElement>(".strip");
      const header = root.querySelector<HTMLElement>(".header");
      if (!page || !strip || !header) return null;
      return tracker.update({
        window: { w: window.innerWidth, h: window.innerHeight },
        header: header.offsetHeight,
        layout: { page: contentSize(page), strip: contentSize(strip) },
      });
    },
  }).then((started) => {
    phone = started;
  });

  let resizeTimer: ReturnType<typeof setTimeout> | undefined;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => phone?.resized(), RESIZE_DEBOUNCE_MS);
  });

  // One delegated listener survives every re-render.
  root.addEventListener("click", (event) => {
    const target =
      event.target instanceof Element ? event.target.closest(".tile, [data-action]") : null;
    if (!(target instanceof HTMLElement)) return;
    if (target.dataset.action === "back") {
      phone?.closeFolder();
    } else if (target.dataset.folderId) {
      phone?.openFolder(target.dataset.folderId);
    } else if (target.dataset.buttonId) {
      phone?.press(target.dataset.buttonId);
      if (target.closest(".strip")) scrollStripToStart(root);
    }
  });
}
