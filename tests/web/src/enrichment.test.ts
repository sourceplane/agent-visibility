// The store's enrichment through the AI binding, and upstream's deterministic
// fallback when the model fails — the path the end-to-end tier and a
// `wrangler dev` with no Cloudflare sign-in take.
import { describe, expect, it } from "vitest";
import { ENRICHED_KEY, RAW_KEY } from "@/src/lib/store";
import { SAMPLE_RESOURCES } from "@/src/lib/content";
import type { Resource } from "@/src/lib/types";
import { FakeAI, makeEnv, workerFetch } from "./fake-env";

const BASE = "https://example.com";

const modelAnswer = (call: { input: { messages: Array<{ content: string }> } }) => ({
  title: "Enriched title",
  summary: "An enriched summary.",
  keyPoints: ["one", "two", "three"],
  topics: ["Docs", "Agents"],
  category: "documentation",
  content: `# Enriched\n\n${call.input.messages[1]?.content.slice(0, 40) ?? ""}`,
});

describe("enrichment", () => {
  it("enriches every sample page once on a cold store and caches it for the TTL", async () => {
    const ai = new FakeAI(modelAnswer);
    const { env, kv } = makeEnv({ ai });
    const res = await workerFetch(env, `${BASE}/llms.txt`);
    expect(res.status).toBe(200);
    expect(ai.calls).toHaveLength(SAMPLE_RESOURCES.length);
    expect(ai.calls[0]?.model).toBe("@cf/test/model");
    expect(kv.ttls.get(ENRICHED_KEY)).toBe(3600);

    const stored = JSON.parse(kv.values.get(ENRICHED_KEY) ?? "[]") as Resource[];
    expect(stored).toHaveLength(SAMPLE_RESOURCES.length);
    expect(stored[0]?.topics).toEqual(["docs", "agents"]);

    // A warm store serves without the model.
    await workerFetch(env, `${BASE}/index.json`);
    expect(ai.calls).toHaveLength(SAMPLE_RESOURCES.length);
  });

  it("falls back to each page's own text when the model fails, cached for 60 s", async () => {
    const { env, kv, ai } = makeEnv();
    const res = await workerFetch(env, `${BASE}/api/resources`);
    const body = (await res.json()) as { count: number; resources: Resource[] };
    expect(body.count).toBe(SAMPLE_RESOURCES.length);
    expect(ai.calls).toHaveLength(SAMPLE_RESOURCES.length);
    for (const resource of body.resources) {
      expect(resource.model).toBe("@cf/test/model (fallback)");
      expect(resource.summary.length).toBeGreaterThan(0);
    }
    expect(kv.ttls.get(ENRICHED_KEY)).toBe(60);

    const md = await workerFetch(env, `${BASE}/${SAMPLE_RESOURCES[0]?.slug}.md`);
    expect(md.status).toBe(200);
  });

  it("enriches a posted page through the model and stores its raw text", async () => {
    const ai = new FakeAI(modelAnswer);
    const { env, kv } = makeEnv({ ai, adminToken: "s3cret" });
    const res = await workerFetch(env, `${BASE}/api/resources`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: "Bearer s3cret" },
      body: JSON.stringify({ slug: "release-notes", title: "Release notes", body: "# Notes\n\nv3 ships." }),
    });
    expect(res.status).toBe(201);
    const created = (await res.json()) as Resource;
    expect(created.title).toBe("Enriched title");
    expect(created.url).toBe(`${BASE}/release-notes`);

    const raws = JSON.parse(kv.values.get(RAW_KEY) ?? "[]") as Array<{ slug: string }>;
    expect(raws.map((r) => r.slug)).toContain("release-notes");

    const llms = await (await workerFetch(env, `${BASE}/llms.txt`)).text();
    expect(llms).toContain("/release-notes.md");
  });
});

describe("writes with no ADMIN_TOKEN stored", () => {
  it("refuses every bearer, as upstream ships", async () => {
    const { env, kv } = makeEnv();
    for (const authorization of ["Bearer anything", "Bearer ", ""]) {
      const post = await workerFetch(env, `${BASE}/api/resources`, {
        method: "POST",
        headers: { "content-type": "application/json", authorization },
        body: JSON.stringify({ slug: "x", body: "hi" }),
      });
      expect(post.status).toBe(401);
      const refresh = await workerFetch(env, `${BASE}/api/refresh`, {
        method: "POST",
        headers: { authorization },
      });
      expect(refresh.status).toBe(401);
    }
    expect(kv.values.has(RAW_KEY)).toBe(false);
  });

  it("refuses a wrong token when one is stored", async () => {
    const { env } = makeEnv({ adminToken: "right" });
    const res = await workerFetch(env, `${BASE}/api/refresh`, {
      method: "POST",
      headers: { authorization: "Bearer wrong" },
    });
    expect(res.status).toBe(401);
  });
});

describe("the site's identity", () => {
  it("names the site from SITE_NAME and SITE_DESCRIPTION on its surfaces", async () => {
    const { env } = makeEnv();
    const site = (await (await workerFetch(env, `${BASE}/api/site`)).json()) as {
      site: { name: string; description: string; origin: string };
      webBotAuthEnabled: boolean;
    };
    expect(site.site).toEqual({
      name: env.SITE_NAME,
      description: env.SITE_DESCRIPTION,
      origin: BASE,
    });
    expect(site.webBotAuthEnabled).toBe(false);
    const llms = await (await workerFetch(env, `${BASE}/llms.txt`)).text();
    expect(llms).toContain(`# ${env.SITE_NAME}`);
  });
});
