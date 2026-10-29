// A DETERMINISTIC STAND-IN FOR WORKERS AI, for testing/e2e.test.sh only.
//
// The product enriches each page through the Worker's `AI` binding
// (apps/web/src/enrichment/index.ts): `env.AI.run(model, { messages:
// [system, user], max_tokens })`, the user message the page's trimmed text,
// answered with `{ response }` holding the enrichment as JSON. Workers AI has
// no local mode and cannot be called offline, so under `wrangler dev` the e2e
// points the `AI` binding at this Worker instead (a service binding to its
// `FakeAI` entrypoint, an RPC method with the binding's own shape). It answers
// with an enrichment that names the model it was asked for and quotes the
// page's first words — or, for a page whose text carries FAIL_ENRICHMENT,
// throws, as a model that fails does, so the product's fallback stands in.
// What that proves is the product's half — the binding, the prompt's reply
// parsed, the store, the surfaces — not that a real model answers the prompt
// with JSON: that is only verified live.
import { WorkerEntrypoint } from "cloudflare:workers";

export function cannedEnrichment(model, text) {
  const words = String(text).split(/\s+/).filter(Boolean).slice(0, 6).join(" ");
  return {
    title: words.replace(/^#\s*/, "") || "Untitled",
    summary: `Enriched by ${model} (the stand-in for Workers AI): ${words}.`,
    keyPoints: ["stand-in point one", "stand-in point two", "stand-in point three"],
    topics: ["Stand-In", "E2E"],
    category: "documentation",
    content: `# ${words}\n\nEnriched by the stand-in.`,
  };
}

export class FakeAI extends WorkerEntrypoint {
  async run(model, inputs) {
    const user = (inputs?.messages ?? []).find((m) => m.role === "user")?.content ?? "";
    if (String(user).includes("FAIL_ENRICHMENT")) throw new Error("stand-in: the model failed");
    return { response: JSON.stringify(cannedEnrichment(model, user)) };
  }
}

export default {
  fetch() {
    return new Response("the Workers AI stand-in", { status: 404 });
  },
};
