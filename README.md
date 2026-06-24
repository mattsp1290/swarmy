# swarmy
Loops made visible

## Serve

`swarmy serve` binds to `127.0.0.1:8080` by default and serves `apps/web/dist`.
Loopback binds do not require a token so local development stays one command.

Binding outside loopback, such as `--host 0.0.0.0`, requires a local token:

```sh
SWARMY_AUTH_TOKEN="$(openssl rand -base64 32)"
export SWARMY_AUTH_TOKEN
swarmy serve --host 0.0.0.0

# or
swarmy serve --host 0.0.0.0 --auth-token "$(openssl rand -base64 32)"
```

API clients send the token with `X-Swarmy-Token: $SWARMY_AUTH_TOKEN` or
`Authorization: Bearer $SWARMY_AUTH_TOKEN`. `/api/auth` reports whether auth is
required and which header is supported; it never returns the token. For browser
dashboard use, open `/#swarmy_token=$SWARMY_AUTH_TOKEN` once. The dashboard
stores the token in browser-local storage, removes it from the address bar, and
sends it as `X-Swarmy-Token` on later API requests. API request bodies are capped
at 1 MiB by default and can be adjusted with `--max-body-bytes`. Requests with a
larger declared `Content-Length` are rejected before JSON parsing, and any actual
body over the configured limit receives `413`.

## Logging and diagnostics

The server emits structured, single-line logs to **stderr** (stdout stays clean
for the JSON/CLI contract). Each API request is logged as `level=info msg="api
request"` with a per-request `request_id`, the HTTP `method`, the `path`, the
resolved `run_id`, and the response `status` (200 or 404). CLI stage writes emit
a `msg="stage transition"` line carrying `run_id`, `bead_id`, `stage`,
`event_id`, and `seq`. Secrets (tokens, bearer headers, `password=`, etc.) are
passed through the shared redactor before logging, so values are emitted as
`[REDACTED]` and never leak into logs.

`swarmy doctor [--repo PATH]` prints a diagnostic report: the canonical repo
path, initialization status, and (when initialized) the `run_id`, `db_path`,
`db_path_trusted`, `config_path`, `created_at`, whether the database file is
present, and up to the 10 most recent error rows. The entire report is run
through the same redactor, so secrets embedded in error messages or paths are
masked. It exits `0` even for an uninitialized repo (reporting that state), `1`
on filesystem/database errors, and `2` on unexpected arguments.
