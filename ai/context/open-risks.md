# agent-visibility — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/agent-visibility/risks-and-open-questions.md`; this page lists
only what is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| AV-G | No live bootstrap yet: the repository created and linked, the token minted, a real `terraform apply`, the lease-published document, a real `wrangler deploy` with the `AI` binding, the token push and the probes are all unproven | OPEN | One bootstrap from a tag against a workspace |
| AV-H | A real Workers AI model must answer upstream's enrichment prompt with JSON; offline only a stand-in answers (and the fallback stands in when it does not) | OPEN | One cold store enriched by the default model on a live deployment |

Accepted, and worth knowing before you change them: AV-A (every surface is
public), AV-B (one shared bearer token for writes), AV-C (the first read of a
cold store runs the model over every page), AV-D (Web Bot Auth off), AV-E (no
local Workers AI), AV-F (the store's limits and KV's eventual consistency).
