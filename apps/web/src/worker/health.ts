/**
 * GET /api/health — not upstream's. The deploy smoke's and the probes' check
 * that the Worker is bound to its store.
 *
 * It reads the enriched store's key from KV and NEVER calls the model: a
 * smoke that fetched /llms.txt on a cold store would run Workers AI over
 * every page on every deploy. `ok` is false (and the route answers 503) only
 * when KV fails — an unbound or unreachable namespace. A cold store is
 * healthy: it is enriched by the first surface a visitor asks for.
 */
import { ENRICHED_KEY } from "../lib/store";
import type { Env } from "../lib/types";

export interface Health {
	ok: boolean;
	/** KV answered the read. */
	kv: boolean;
	/** The Workers AI binding is bound (it is not called). */
	ai: boolean;
	/** An enriched store is cached. */
	cached: boolean;
	/** How many enriched pages the cached store holds. */
	pages: number;
}

export async function health(env: Env): Promise<Health> {
	const ai = typeof env.AI?.run === "function";
	try {
		const stored = await env.VISIBILITY_CACHE.get(ENRICHED_KEY, "json");
		const pages = Array.isArray(stored) ? stored.length : 0;
		return { ok: true, kv: true, ai, cached: pages > 0, pages };
	} catch {
		return { ok: false, kv: false, ai, cached: false, pages: 0 };
	}
}
