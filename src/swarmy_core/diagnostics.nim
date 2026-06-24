import std/strutils

const SecretMarkers = [
  "authorization: bearer ",
  "x-swarmy-token: ",
  "swarmy_token=",
  "auth_token=",
  "access_token=",
  "api_key=",
  "password=",
  "token=",
  "secret="
]

const SecretJsonKeys = [
  "authorization",
  "x-swarmy-token",
  "swarmy_token",
  "auth_token",
  "access_token",
  "api_key",
  "password",
  "token",
  "secret"
]

proc redactMarker(value, marker: string): string =
  result = value
  let loweredMarker = marker.toLowerAscii()
  var searchFrom = 0
  while searchFrom < result.len:
    let lowered = result.toLowerAscii()
    let markerStart = lowered.find(loweredMarker, searchFrom)
    if markerStart < 0:
      break

    let secretStart = markerStart + marker.len
    var secretEnd = secretStart
    while secretEnd < result.len and result[secretEnd] notin {
      ' ', '\t', '\n', '\r', '"', '\'', ',', ';', '&', '}'
    }:
      inc secretEnd

    if secretEnd == secretStart:
      searchFrom = secretStart
      continue

    result = result[0 ..< secretStart] & "[REDACTED]" & result[secretEnd .. ^1]
    searchFrom = secretStart + "[REDACTED]".len

proc redactJsonKey(value, key: string): string =
  result = value
  let quotedKey = "\"" & key.toLowerAscii() & "\""
  var searchFrom = 0
  while searchFrom < result.len:
    let lowered = result.toLowerAscii()
    let keyStart = lowered.find(quotedKey, searchFrom)
    if keyStart < 0:
      break

    var i = keyStart + quotedKey.len
    while i < result.len and result[i] in {' ', '\t', '\n', '\r'}:
      inc i
    if i >= result.len or result[i] != ':':
      searchFrom = keyStart + quotedKey.len
      continue
    inc i
    while i < result.len and result[i] in {' ', '\t', '\n', '\r'}:
      inc i

    let quote = i < result.len and result[i] in {'"', '\''}
    if quote:
      inc i
    let secretStart = i
    while i < result.len and (
      if quote:
        result[i] notin {'"', '\''}
      else:
        result[i] notin {' ', '\t', '\n', '\r', ',', ';', '&', '}'}
    ):
      inc i

    if i == secretStart:
      searchFrom = secretStart
      continue

    result = result[0 ..< secretStart] & "[REDACTED]" & result[i .. ^1]
    searchFrom = secretStart + "[REDACTED]".len

proc redactDiagnostic*(value: string): string =
  result = value
  for marker in SecretMarkers:
    result = result.redactMarker(marker)
  for key in SecretJsonKeys:
    result = result.redactJsonKey(key)
