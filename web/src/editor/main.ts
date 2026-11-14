import "./editor.css";
import { EditorApi } from "./api";
import { startEditor } from "./controller";
import { takeEditorKey } from "./editor-key";
import { isDirty } from "./render";

const root = document.getElementById("app");

if (root) {
  void startEditor({
    root,
    api: new EditorApi(
      window.fetch.bind(window),
      takeEditorKey({
        location: window.location,
        // Lazy: reading `sessionStorage` itself throws when site data is blocked.
        storage: {
          getItem: (key) => window.sessionStorage.getItem(key),
          setItem: (key, value) => {
            window.sessionStorage.setItem(key, value);
          },
        },
        replaceUrl: (url) => {
          window.history.replaceState(null, "", url);
        },
      }),
    ),
    confirm: (message) => window.confirm(message),
  }).then((editor) => {
    window.addEventListener("keydown", (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
        event.preventDefault();
        void editor.save();
      }
    });
    window.addEventListener("beforeunload", (event) => {
      if (isDirty(editor.model)) event.preventDefault();
    });
  });
}
