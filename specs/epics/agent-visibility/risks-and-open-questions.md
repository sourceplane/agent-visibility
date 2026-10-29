# agent-visibility — risks and open questions

## AV-A — Every surface is public (ACCEPTED, by design)

The surfaces exist to be read by anyone, agents first: `/llms.txt`, the
index, every page's Markdown and JSON-LD, and the dashboard. Nothing posted
to the store is private. The product's README says so first, and its
operating contract's "Who can do what" table repeats it.

## AV-B — Writes behind one shared bearer token (ACCEPTED)

`ADMIN_TOKEN` is one token, compared by upstream's Worker on the two
mutating routes, with no lockout or rate limit of its own. It is upstream's
own guard and the only one a product can switch on with a secret alone.
With none stored the routes refuse every write, as upstream ships.
Rotating it is setting a new value and redeploying; the deploy replaces the
Worker's secret.

## AV-C — The model on the first read (ACCEPTED)

A cold store is enriched on the first request that needs it, one model call
per page (five for the sample), so that request is slow and spends Workers
AI usage on the account. Upstream's design; the cache then serves for an
hour. The deploy smoke and the probes read `/api/health`, which never calls
the model, so a deploy does not warm the cache or spend on it.

## AV-D — Web Bot Auth stays off (ACCEPTED)

Upstream ships the identity surface disabled and its directory holding one
illustrative key ("replace me"). Turning it on as shipped would publish a
key nobody holds. The baseline keeps `ENABLE_WEB_BOT_AUTH: "false"`; an
owner who wants it replaces `SAMPLE_AGENT_KEYS` and sets the var.

## AV-E — Workers AI in local development (ACCEPTED)

Workers AI has no local mode. Under `wrangler dev` with no Cloudflare
sign-in every model call fails and upstream's fallback enriches each page
from its own text; the surfaces serve, their `model` field reading
`… (fallback)`, cached for 60 s. The end-to-end tier relies on exactly
that, and proves it.

## AV-F — The store's limits (ACCEPTED)

Upstream caps the store at 100 pages of 100 kB each, and keeps the whole
enriched store in one KV value (KV's 25 MiB value limit is well above it).
KV is eventually consistent across locations: a page posted in one region
can take up to a minute to appear in another. Upstream's design.

## Open questions

None blocking.
