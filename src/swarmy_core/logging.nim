import std/strutils

import swarmy_core/diagnostics

type
  LogLevel* = enum
    lvlInfo
    lvlWarn
    lvlError

proc levelName*(l: LogLevel): string =
  case l
  of lvlInfo: "info"
  of lvlWarn: "warn"
  of lvlError: "error"

proc needsQuoting(value: string): bool =
  if value.len == 0:
    return true
  for ch in value:
    if ch == ' ' or ch == '"' or ch == '=':
      return true
  false

proc renderField(key, value: string): string =
  let redacted = redactDiagnostic(value)
  if needsQuoting(redacted):
    key & "=\"" & redacted.replace("\"", "\\\"") & "\""
  else:
    key & "=" & redacted

proc renderLogLine*(
  level: LogLevel,
  message: string,
  fields: openArray[(string, string)] = @[]
): string =
  result = "level=" & levelName(level)
  result.add " msg=\"" & redactDiagnostic(message).replace("\"", "\\\"") & "\""
  for (key, value) in fields:
    result.add " " & renderField(key, value)

proc emitLog*(
  level: LogLevel,
  message: string,
  fields: openArray[(string, string)] = @[]
) =
  stderr.write(renderLogLine(level, message, fields) & "\n")
  stderr.flushFile()
