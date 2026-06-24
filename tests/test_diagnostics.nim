import std/[strutils, unittest]

import swarmy_core/diagnostics

suite "diagnostics":
  test "redacts common token and secret diagnostics":
    let message = "Authorization: Bearer abc123 token=plain secret=hunter2 " &
      "access_token=access-value api_key=key-value password=pw-value " &
      """{"swarmy_token":"hash-token","auth_token": "json-token","token" : "spaced-token"}"""

    let redacted = redactDiagnostic(message)

    check "abc123" notin redacted
    check "plain" notin redacted
    check "hunter2" notin redacted
    check "access-value" notin redacted
    check "key-value" notin redacted
    check "pw-value" notin redacted
    check "hash-token" notin redacted
    check "json-token" notin redacted
    check "spaced-token" notin redacted
    check redacted.count("[REDACTED]") == 9

  test "redacts a bare bearer token without an authorization prefix":
    let redacted = redactDiagnostic("provider auth failed: Bearer sk-live-abc123")
    check "sk-live-abc123" notin redacted
    check "[REDACTED]" in redacted
