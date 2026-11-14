import { resolve } from "node:path";
import { defineConfig } from "vitest/config";

const agent = "http://127.0.0.1:8765";

export default defineConfig({
  build: {
    target: "es2020",
    rollupOptions: {
      input: {
        phone: resolve(import.meta.dirname, "index.html"),
        editor: resolve(import.meta.dirname, "editor.html"),
      },
    },
  },
  server: {
    proxy: {
      "/api": agent,
      "/icons": agent,
      "/ws": { target: agent, ws: true },
    },
  },
  test: {
    environment: "jsdom",
    include: ["tests/**/*.test.ts"],
  },
});
