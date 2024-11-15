import { defineConfig } from "vite";
import solidPlugin from "vite-plugin-solid";
import devtools from "solid-devtools/vite";

export default defineConfig({
  plugins: [
    /* 
    Uncomment the following line to enable solid-devtools.
    For more info see https://github.com/thetarnav/solid-devtools/tree/main/packages/extension#readme
    */
    devtools({
      autoname: true,
      locator: {
        targetIDE: "vscode",
        key: "Ctrl",
        jsxLocation: true,
        componentLocation: true,
      },
    }),
    solidPlugin(),
  ],
  server: {
    port: 3000,
    proxy: {
      "/api": {
        target: "http://localhost:3080",
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, ""),
      },
    },
  },
  build: {
    target: "esnext",
  },
});
