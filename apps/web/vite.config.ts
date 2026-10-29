// The dashboard's build: Vite and the React plugin, upstream's client build
// without @cloudflare/vite-plugin. The Worker is not built here — wrangler
// bundles src/worker/index.ts on deploy (and under `wrangler dev`) and serves
// this output as its Static Assets (wrangler.jsonc → assets.directory).
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
	plugins: [react()],
	build: {
		outDir: "dist/client",
		emptyOutDir: true,
	},
});
