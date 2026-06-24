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
