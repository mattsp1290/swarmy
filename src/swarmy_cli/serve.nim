import std/[os, strutils]

import swarmy_server/app as server_app

import ./dispatch_types

const
  DefaultHost* = "127.0.0.1"
  DefaultPort* = 8080
  DefaultStaticDir* = "apps" / "web" / "dist"

type ServeOptions* = object
  host*: string
  port*: int
  staticDir*: string

proc defaultServeOptions*(): ServeOptions =
  ServeOptions(
    host: DefaultHost,
    port: DefaultPort,
    staticDir: DefaultStaticDir
  )

proc preview*(options: ServeOptions): string =
  "swarmy serve: http://" & options.host & ":" & $options.port &
    " static " & options.staticDir & "\n"

proc parsePort(raw: string): tuple[ok: bool, value: int, error: string] =
  try:
    let port = parseInt(raw)
    if port < 1 or port > 65535:
      return (false, 0, "swarmy serve: --port must be between 1 and 65535\n")
    (true, port, "")
  except ValueError:
    (false, 0, "swarmy serve: --port must be an integer\n")

proc parseServeArgs*(args: seq[string]): tuple[
  ok: bool,
  options: ServeOptions,
  error: string
] =
  result = (true, defaultServeOptions(), "")
  var i = 0
  while i < args.len:
    case args[i]
    of "--host":
      if i + 1 >= args.len or args[i + 1].startsWith("-"):
        return (false, result.options, "swarmy serve: --host requires a value\n")
      result.options.host = args[i + 1]
      i += 2
    of "--port":
      if i + 1 >= args.len or args[i + 1].startsWith("-"):
        return (false, result.options, "swarmy serve: --port requires a value\n")
      let parsed = parsePort(args[i + 1])
      if not parsed.ok:
        return (false, result.options, parsed.error)
      result.options.port = parsed.value
      i += 2
    of "--static-dir":
      if i + 1 >= args.len or args[i + 1].startsWith("-"):
        return (false, result.options, "swarmy serve: --static-dir requires a value\n")
      result.options.staticDir = args[i + 1]
      i += 2
    else:
      return (
        false,
        result.options,
        "swarmy serve: unexpected argument '" & args[i] & "'\n"
      )

proc run*(args: seq[string]): CliResult =
  let parsed = parseServeArgs(args)
  if not parsed.ok:
    return CliResult(exitCode: 2, error: parsed.error)

  CliResult(exitCode: 0, output: parsed.options.preview)

proc serveBlocking*(args: seq[string]): CliResult =
  let parsed = parseServeArgs(args)
  if not parsed.ok:
    return CliResult(exitCode: 2, error: parsed.error)

  stdout.write(parsed.options.preview)
  stdout.flushFile()
  server_app.serve(ServerConfig(
    address: parsed.options.host,
    port: parsed.options.port,
    staticDir: parsed.options.staticDir
  ))
  CliResult(exitCode: 0)
