import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { fileURLToPath } from "node:url";

// React Native code rendered on the web: `react-native` resolves to `react-native-web`,
// and `.web.*` files win so libraries such as react-native-svg use their DOM implementations.
const extensions = [".web.tsx", ".web.ts", ".web.mjs", ".web.js", ".tsx", ".ts", ".mjs", ".js", ".jsx", ".json"];

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: [
      { find: /^react-native$/, replacement: "react-native-web" },
      { find: "@react-native/assets-registry/registry", replacement: fileURLToPath(new URL("./src/shims/assets-registry.ts", import.meta.url)) },
    ],
    extensions,
  },
  optimizeDeps: {
    rolldownOptions: { resolve: { extensions } },
  },
  define: {
    __DEV__: JSON.stringify(process.env.NODE_ENV !== "production"),
    global: "globalThis",
  },
  // The Julia server (src/server.jl) serves this directory.
  build: { outDir: "../public", emptyOutDir: true, chunkSizeWarningLimit: 1024 },
  // `pnpm dev`: hot-reloading UI on :5173, API calls proxied to `julia --project=. run.jl`.
  server: { proxy: { "/api": "http://127.0.0.1:8000" } },
});
