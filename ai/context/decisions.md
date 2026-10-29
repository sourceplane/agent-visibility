# agent-visibility — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | Upstream's Worker, enrichment, store, sample pages and dashboard are kept as written | A port, not a rewrite | IMPLEMENTATION-STATUS |
| 2 | The dashboard is built by Vite alone; wrangler bundles the Worker | The composition deploys a Worker entrypoint and an assets directory; `@cloudflare/vite-plugin` would be a second deploy path | design §2 |
| 3 | Workers AI through the keyless `AI` binding; `pnpm dev` runs `wrangler dev --local` | A fresh product enriches with no key; upstream's dev server has remote bindings off too | design §4, risks AV-E |
| 4 | `ADMIN_TOKEN` is an optional Orun secret handed to the Worker as a Worker secret; never a var, never a build value | A product deploys and serves before its owner chooses a token; writes stay refused until then, as upstream ships | `apps/web/component.yaml`, `tooling/wire/worker-secrets.mjs` |
| 5 | `/api/health` reads the store and never calls the model | The deploy smoke reads it on every deploy; a model call there would spend Workers AI each time | `apps/web/src/worker/health.ts` |
| 6 | Web Bot Auth stays off | Its directory is upstream's illustrative sample key | risks AV-D |
| 7 | The namespace id reaches the Worker through the wiring document, rendered per environment; `wrangler.jsonc` is committed as the fixture render | The deploy-time render every binding in this programme uses; the deploy lane checks the config exists before it builds | `apps/web/wrangler.template.jsonc` |
| 8 | One landing (`01-product`) then the record (`02-docs`); `web` → `cloudflare-kv` enforced on main, advisory on a pull request | The plan, not a landing boundary, orders the namespace before the Worker | `repo-blueprint.yaml` |
| 9 | Two brokered secrets: `workers-deploy` applies the namespace and deploys the Worker | That token covers KV Storage write; Workers AI needs no key | `blueprint.yaml` |
| 10 | The product's name comes from two seams (`SITE_NAME` in the wrangler template, the dashboard's `<title>`); the dashboard's kicker, the template's name and the `agent-visibility/0.1` index protocol stay upstream's | The rename rewrites two literals and protects the two upstream names that begin with the slug | `tooling/rebrand/rebrand.mjs` |
| 11 | stack-tectonic 0.19.0, not 0.20.0 | One job per lane: 0.20.0's lane-scoped install would save nothing | `intent.yaml` |
| 12 | The console asks for no domain and reads `subdomain` from the Cloudflare connection | The site goes live on workers.dev; the subdomain belongs to the account | `blueprint.yaml` |
| 13 | Forked from edge-middleware-recipes' shape (a Hono Worker with optional secrets), its tree built on r2-explorer's and ai-artifacts' (Static Assets, a KV root, the AI binding) | edge-middleware-recipes has no Static Assets and no Terraform root | IMPLEMENTATION-STATUS |
