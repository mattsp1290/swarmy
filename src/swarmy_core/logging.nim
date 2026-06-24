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
    if ch in {' ', '"', '=', '\n', '\r', '\t'} or ch < ' ':
      return true
  false

proc escapeValue(value: string): string =
  ## Escapes characters that would otherwise break the single-line, structured
  ## log format. Newlines/CR are escaped so a field value can never forge a
  ## second log record (log injection).
  result = newStringOfCap(value.len + 2)
  for ch in value:
    case ch
    of '"': result.add "\\\""
    of '\\': result.add "\\\\"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else:
      if ch < ' ':
        result.add "\\x" & toHex(ord(ch), 2)
      else:
        result.add ch

proc renderField(key, value: string): string =
  let redacted = redactDiagnostic(value)
  if needsQuoting(redacted):
    key & "=\"" & escapeValue(redacted) & "\""
  else:
    key & "=" & redacted

proc renderLogLine*(
  level: LogLevel,
  message: string,
  fields: openArray[(string, string)] = @[]
): string =
  result = "level=" & levelName(level)
  result.add " msg=\"" & escapeValue(redactDiagnostic(message)) & "\""
  for (key, value) in fields:
    result.add " " & renderField(key, value)

proc emitLog*(
  level: LogLevel,
  message: string,
  fields: openArray[(string, string)] = @[]
) =
  stderr.write(renderLogLine(level, message, fields) & "\n")
  stderr.flushFile()
