// /api/health — not upstream's: the deploy smoke's check. It reads the store
// through the KV binding and never calls the model.
import { describe, expect, it } from "vitest";
import { ENRICHED_KEY } from "@/src/lib/store";
import { FakeAI, makeEnv, workerFetch } from "./fake-env";

const BASE = "https://example.com";

describe("/api/health", () => {
  it("is ok on a cold store, and does not enrich it", async () => {
    const ai = new FakeAI(() => ({ title: "never" }));
    const { env, kv } = makeEnv({ ai });
    const res = await workerFetch(env, `${BASE}/api/health`);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, kv: true, ai: true, cached: false, pages: 0 });
    expect(ai.calls).toHaveLength(0);
    expect(kv.values.has(ENRICHED_KEY)).toBe(false);
  });

  it("counts the pages of a warm store", async () => {
    const { env, kv } = makeEnv();
    kv.values.set(ENRICHED_KEY, JSON.stringify([{ slug: "a" }, { slug: "b" }]));
    const res = await workerFetch(env, `${BASE}/api/health`);
    expect(await res.json()).toMatchObject({ ok: true, cached: true, pages: 2 });
  });

  it("answers 503 when KV fails", async () => {
    const { env, kv } = makeEnv();
    kv.failing = true;
    const res = await workerFetch(env, `${BASE}/api/health`);
    expect(res.status).toBe(503);
    expect(await res.json()).toMatchObject({ ok: false, kv: false });
  });

  it("reports a missing AI binding without failing", async () => {
    const { env } = makeEnv();
    const unbound = { ...env, AI: undefined as unknown as Ai };
    const res = await workerFetch(unbound, `${BASE}/api/health`);
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true, ai: false });
  });
});
