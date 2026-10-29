# web-tests

The site's vitest suite — upstream's surface and API tests over an in-memory KV store and a stand-in model, the health route, the enrichment and its fallback, and the wrangler config's routes and bindings

The test suite for **web**. It deploys nothing: its lane installs, builds and runs the tests.

|              |                      |
| ------------ | -------------------- |
| Type         | `turbo-package`      |
| Source       | `tests/web`          |
| Package      | `@app/web-tests`     |
| Environments | `dev`: `quick-check` |

## Depends on

- (none)

## Depended on by

- (none)
