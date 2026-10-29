# web

The site — every agent surface and the dashboard, upstream's Worker on Cloudflare Workers + Static Assets, over the KV store and Workers AI, per environment

A Cloudflare Worker with Static Assets (server rendering plus static files), deployed per environment by its CI lane.

|              |                                                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Type         | `cloudflare-workers-assets-turbo`                                                                                  |
| Source       | `apps/web`                                                                                                         |
| Package      | `@app/web`                                                                                                         |
| Environments | `dev`: `verify` · `stage`: `verify`, `deploy` on a push to `main` · `prod`: `verify`, `deploy` on a push to `main` |

## Depends on

- **cloudflare-kv** — Provisions the Cloudflare KV namespace the site's content store and its enrichment live in (stage and prod)

## Depended on by

- (none)
