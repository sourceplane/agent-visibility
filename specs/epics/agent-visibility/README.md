# Epic: agent-visibility (AV)

**Cloudflare's Agent Visibility template is one Hono Worker that makes a site's content readable by AI agents on every surface they look at — `/llms.txt` and `/llms-full.txt`, a typed `/index.json`, per-page Markdown (`/<slug>.md`) and JSON-LD (`/<slug>.jsonld`, `/jsonld`), and a `/robots.txt` that names the AI crawlers it welcomes — every one of them carrying a `Content-Signal` header that says how the content may be used. Each page is enriched once by Workers AI (a title, a summary, key points, topics, a clean Markdown body) and the result cached in Workers KV; a small React dashboard at `/` previews every surface. Here the KV namespace is per environment from Terraform; the admin token that opens its writes is an optional Orun secret, pushed to the Worker as a Worker secret — writes refused without it, as upstream ships it; and the wrangler config is rendered per environment from the KV root's wiring document.**

The port keeps the Worker, its surfaces, its enrichment (and its deterministic fallback), its sample content, its dashboard, its routes and its defaults unchanged. It adds the monorepo wrapper, `/api/health` (the smoke's and the probes' store check, which never calls the model), the dashboard's build by Vite alone into the Worker's assets, a test package that drives upstream's Worker over an in-memory KV store and a stand-in model, the KV Terraform root, the deploy contract and the admin token's path to the Worker — and makes the repository an Orun baseline.

## Status

| Field | Value |
|-------|-------|
| Status | In progress — AV0–AV3 shipped; AV4 (the baseline) next |
| Cluster | **AV** (AV0–AV4) |
| Owner(s) | `apps/web` (`src/worker`, `src/enrichment`, `src/lib`, `src/react-app`, `/api/health`, the wrangler template) · `tests/web` · `infra/terraform/cloudflare-kv` |
| Builds on | `edge-middleware-recipes` (a Hono Worker on Orun with its optional secrets as runtime secrets); `kv-redis-starter` and `ai-artifacts` (the Cirrus KV root `cloudflare-kv`, its wiring render, the keyless `AI` binding and its one-landing bootstrap); `r2-explorer` (optional Orun secrets handed to a Static Assets Worker as Worker secrets) |
| Upstream | [cloudflare/templates `agent-visibility-template`](https://github.com/cloudflare/templates/tree/main/agent-visibility-template) (MIT, © 2018 Cloudflare, Inc.) at `7ae5750` |
| Changes | The KV namespace from Terraform, rendered per environment; the admin token an optional Orun secret pushed as a Worker secret; the dashboard built by Vite alone (no `@cloudflare/vite-plugin`); `/api/health`; `SITE_NAME` the product's; tests over an in-memory store; the KV root, the deploy contract |
| Decisions locked | (1) The Worker, the surfaces, the enrichment and the dashboard stay upstream's code (design §2). (2) Writes stay closed until `ADMIN_TOKEN` is stored (design §3). (3) The token is an optional Orun secret, pushed to the Worker as a Worker secret; the build never sees it (design §3). (4) Workers AI through the keyless `AI` binding — no key, no Orun resource (design §4). (5) Web Bot Auth stays off (design §6). (6) The store before the Worker on main: cloudflare-kv → web, enforced; advisory on pull requests. |
| Gate | AV2 applies only with a linked workspace (a Cloudflare connection); verified by `terraform validate` and, from AV4, the offline end-to-end tier. |

## Read order

1. `design.md` — what maps to what, the admin token, the bindings, what is out of scope
2. `implementation-plan.md` — the milestones and what "done" means for each
3. `risks-and-open-questions.md` — what could go wrong and what was decided
4. `IMPLEMENTATION-STATUS.md` — what actually shipped (kept distinct from intent)

## Milestones at a glance

| Milestone | What it lands | Done when |
|---|---|---|
| AV0 — the spec | this doc set, the task contracts, the repository's intent, CI and tooling | merged on `main` |
| AV1 — the site on Workers | `apps/web`, the rendered wrangler config, `tests/web`, the Worker-secrets step | typecheck, lint, test and build green; the Worker serves every surface and the dashboard over the KV binding, writes refused and then admitted with the token |
| AV2 — the KV namespace from Terraform | `infra/terraform/cloudflare-kv` | the root validates; its wiring key matches the template |
| AV3 — ready to instantiate | README, as-built status | a reader can run, test, preview, add pages and deploy |
| AV4 — a baseline | card, build document, rename engine, bootstrap tooling, the product's README and context pack, component docs, tests, `baseline.yml` / `tag.yml` | a new product goes from nothing to live on stage and prod in one landing; Baseline CI green; tagged `baseline-v1` |
