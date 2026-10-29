# web — architecture

Built by the turbo pipeline from `apps/web` and deployed with wrangler.

|                    |                                    |
| ------------------ | ---------------------------------- |
| Worker config      | `apps/web/wrangler.template.jsonc` |
| Entry              | `src/worker/index.ts`              |
| Compatibility date | `2025-10-08`                       |

## Bindings

| Binding            | Kind                 | Source                                  |
| ------------------ | -------------------- | --------------------------------------- |
| `VISIBILITY_CACHE` | Workers KV namespace | `app_kv_id` from `cloudflare-kv`        |
| `AI`               | Workers AI           | account-level; no resource to provision |
| `ASSETS`           | Static assets        | `dist/client`                           |

Identifiers marked _from_ a component are filled in at deploy time from
that component's published outputs for the environment being deployed.

## Variables

`AI_MODEL`, `CONTENT_SIGNAL`, `ENABLE_WEB_BOT_AUTH`, `ENRICHMENT_CACHE_TTL`, `SITE_DESCRIPTION`, `SITE_NAME`.

## Wiring

Resolved at deploy time from secrets the infrastructure lanes publish (names only):

- `WIRING_CLOUDFLARE_KV_PROD`
- `WIRING_CLOUDFLARE_KV_STAGE`

## Secrets resolved by the lane (names only)

- `ADMIN_TOKEN` (optional)
