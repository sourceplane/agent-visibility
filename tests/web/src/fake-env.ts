// The Worker's bindings, in memory: a KV namespace with the three calls
// upstream's store makes (get as JSON, put with an expiry, delete) and a
// stand-in for the Workers AI binding that answers — or fails — as a test
// tells it to. Upstream's suite ran under @cloudflare/vitest-pool-workers
// against miniflare's KV; this runs the same Worker in node.
import worker from "@/src/worker/index";
import type { Env } from "@/src/lib/types";

export class FakeKV {
  readonly values = new Map<string, string>();
  readonly ttls = new Map<string, number | undefined>();
  /** Every call fails, as an unbound or unreachable namespace would. */
  failing = false;

  async get(key: string, type?: "text" | "json"): Promise<unknown> {
    if (this.failing) throw new Error("KV unavailable");
    const value = this.values.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) : value;
  }

  async put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void> {
    if (this.failing) throw new Error("KV unavailable");
    this.values.set(key, value);
    this.ttls.set(key, options?.expirationTtl);
  }

  async delete(key: string): Promise<void> {
    if (this.failing) throw new Error("KV unavailable");
    this.values.delete(key);
    this.ttls.delete(key);
  }
}

export interface AiCall {
  model: string;
  input: { messages: Array<{ role: string; content: string }> };
}

/** Answers each run with `answer(input)`; an Error is thrown instead. */
export class FakeAI {
  readonly calls: AiCall[] = [];
  constructor(private readonly answer: (call: AiCall) => unknown = () => new Error("no model")) {}

  async run(model: string, input: AiCall["input"]): Promise<{ response: unknown }> {
    const call = { model, input };
    this.calls.push(call);
    const result = this.answer(call);
    if (result instanceof Error) throw result;
    return { response: result };
  }
}

export interface TestEnv {
  env: Env;
  kv: FakeKV;
  ai: FakeAI;
}

export function makeEnv(options: { adminToken?: string; ai?: FakeAI } = {}): TestEnv {
  const kv = new FakeKV();
  const ai = options.ai ?? new FakeAI();
  const env: Env = {
    AI: ai as unknown as Ai,
    VISIBILITY_CACHE: kv as unknown as KVNamespace,
    SITE_NAME: "Test Docs",
    SITE_DESCRIPTION: "Documentation for the test suite.",
    AI_MODEL: "@cf/test/model",
    ENRICHMENT_CACHE_TTL: "3600",
    CONTENT_SIGNAL: "ai-input=yes, search=yes, ai-train=no",
    ENABLE_WEB_BOT_AUTH: "false",
    ...(options.adminToken === undefined ? {} : { ADMIN_TOKEN: options.adminToken }),
  };
  return { env, kv, ai };
}

const ctx = {
  waitUntil: () => {},
  passThroughOnException: () => {},
  props: {},
} as unknown as ExecutionContext;

/** The Worker's own fetch, as the runtime calls it. */
export function workerFetch(env: Env, url: string, init?: RequestInit): Promise<Response> {
  return Promise.resolve(worker.fetch(new Request(url, init), env, ctx));
}
