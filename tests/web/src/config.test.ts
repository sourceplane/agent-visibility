// The committed wrangler config — the fixture render of wrangler.template.jsonc
// — keeps upstream's routes and bindings: the surfaces and the API reach the
// Worker before the assets, the dashboard is a single-page app, and the
// Worker is bound to Workers AI and its KV store.
import { readFileSync } from "node:fs";
import * as path from "node:path";
import { parse } from "jsonc-parser";
import { describe, expect, it } from "vitest";

const app = path.resolve(__dirname, "../../../apps/web");
interface WranglerConfig {
  main: string;
  assets: { directory: string; not_found_handling: string; run_worker_first: string[] };
  ai: { binding: string };
  kv_namespaces: Array<{ binding: string; id: string }>;
  vars: Record<string, string>;
}
const read = <T = WranglerConfig>(file: string) => parse(readFileSync(path.join(app, file), "utf8")) as T;

const UPSTREAM_WORKER_FIRST = [
  "/.well-known/web-bot-auth/*",
  "/api",
  "/api/*",
  "/index.json",
  "/jsonld",
  "/llms-full.txt",
  "/llms.txt",
  "/robots.txt",
  "/*.jsonld",
  "/*.md",
];

describe.each(["wrangler.jsonc", "wrangler.template.jsonc"])("%s", (file) => {
  const config = read(file);

  it("runs upstream's Worker over the dashboard's assets", () => {
    expect(config.main).toBe("src/worker/index.ts");
    expect(config.assets.directory).toBe("dist/client");
    expect(config.assets.not_found_handling).toBe("single-page-application");
    expect(config.assets.run_worker_first).toEqual(UPSTREAM_WORKER_FIRST);
  });

  it("binds Workers AI and the KV store", () => {
    expect(config.ai).toEqual({ binding: "AI" });
    expect(config.kv_namespaces).toHaveLength(1);
    expect(config.kv_namespaces[0]?.binding).toBe("VISIBILITY_CACHE");
  });

  it("keeps upstream's vars, with Web Bot Auth off and no secret among them", () => {
    expect(Object.keys(config.vars).sort()).toEqual(
      ["AI_MODEL", "CONTENT_SIGNAL", "ENABLE_WEB_BOT_AUTH", "ENRICHMENT_CACHE_TTL", "SITE_DESCRIPTION", "SITE_NAME"],
    );
    expect(config.vars.ENABLE_WEB_BOT_AUTH).toBe("false");
    expect(config.vars.CONTENT_SIGNAL).toBe("ai-input=yes, search=yes, ai-train=no");
    expect(config.vars.AI_MODEL).toBe("@cf/meta/llama-3.3-70b-instruct-fp8-fast");
  });
});

describe("the wiring", () => {
  it("takes the namespace id from the cloudflare-kv root's document", () => {
    expect(read("wrangler.template.jsonc").kv_namespaces[0]?.id).toBe("@@wiring(cloudflare-kv/__ENV__:app_kv_id)@@");
  });

  it("commits the fixture's stage render", () => {
    const fixture = read<Record<string, { app_kv_id: string }>>("wiring.fixture.json");
    expect(read("wrangler.jsonc").kv_namespaces[0]?.id).toBe(fixture["cloudflare-kv/stage"]?.app_kv_id);
  });
});
