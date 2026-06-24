import std/[strutils, unittest]

import swarmy_core/logging

suite "structured logging":
  test "level names map to lowercase strings":
    check levelName(lvlInfo) == "info"
    check levelName(lvlWarn) == "warn"
    check levelName(lvlError) == "error"

  test "renders a single line with quoted message and bare fields":
    let line = renderLogLine(lvlInfo, "api request", {
      "request_id": "abc123",
      "status": "200"
    })
    check line == "level=info msg=\"api request\" request_id=abc123 status=200"
    check "\n" notin line

  test "redacts secrets in message and field values":
    let line = renderLogLine(lvlError, "token=sekret123 failed", {
      "header": "authorization: Bearer abc123"
    })
    check "[REDACTED]" in line
    check "sekret123" notin line
    check "abc123" notin line

  test "quotes values containing spaces and preserves field order":
    let line = renderLogLine(lvlInfo, "msg", {
      "first": "a b c",
      "second": "plain"
    })
    check "first=\"a b c\"" in line
    let firstIdx = line.find("first=")
    let secondIdx = line.find("second=")
    check firstIdx >= 0
    check secondIdx > firstIdx

  test "quotes empty values":
    let line = renderLogLine(lvlInfo, "msg", {"empty": ""})
    check "empty=\"\"" in line

  test "escapes embedded quotes in field values":
    let line = renderLogLine(lvlInfo, "msg", {"q": "has\"quote"})
    check "q=\"has\\\"quote\"" in line
