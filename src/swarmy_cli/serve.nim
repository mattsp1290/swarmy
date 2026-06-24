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
  repo*: string
  authToken*: string
  maxBodyBytes*: int

proc defaultServeOptions*(): ServeOptions =
  ServeOptions(
    host: DefaultHost,
    port: DefaultPort,
    staticDir: DefaultStaticDir,
    repo: ".",
    authToken: getEnv("SWARMY_AUTH_TOKEN"),
    maxBodyBytes: 1024 * 1024
  )

proc preview*(options: ServeOptions): string =
  result = "swarmy serve: http://" & options.host & ":" & $options.port &
    " static " & options.staticDir
  if options.authToken.len > 0:
    result.add(" auth required")
  result.add("\n")

proc validateStaticDir*(staticDir: string): tuple[ok: bool, error: string] =
  let indexPath = staticDir / "index.html"
  if not fileExists(indexPath):
    return (
      false,
      "swarmy serve: web app build not found at " & indexPath &
        " (run `npm run build --workspace apps/web` or pass --static-dir)\n"
    )
  (true, "")

proc parsePort(raw: string): tuple[ok: bool, value: int, error: string] =
  try:
    let port = parseInt(raw)
    if port < 1 or port > 65535:
      return (false, 0, "swarmy serve: --port must be between 1 and 65535\n")
    (true, port, "")
  except ValueError:
    (false, 0, "swarmy serve: --port must be an integer\n")

proc parseMaxBodyBytes(raw: string): tuple[ok: bool, value: int, error: string] =
  try:
    let maxBytes = parseInt(raw)
    if maxBytes < 0:
      return (
        false,
        0,
        "swarmy serve: --max-body-bytes must be zero or greater\n"
      )
    (true, maxBytes, "")
  except ValueError:
    (false, 0, "swarmy serve: --max-body-bytes must be an integer\n")

proc validateBindAuth*(options: ServeOptions): tuple[ok: bool, error: string] =
  if options.authToken.len == 0 and not server_app.isLoopbackBindAddress(options.host):
    return (
      false,
      "swarmy serve: --auth-token or SWARMY_AUTH_TOKEN is required when binding outside loopback\n"
    )
  (true, "")

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
      if args[i + 1].len == 0:
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
      if args[i + 1].len == 0:
        return (false, result.options, "swarmy serve: --static-dir requires a value\n")
      result.options.staticDir = args[i + 1]
      i += 2
    of "--repo":
      if i + 1 >= args.len or args[i + 1].startsWith("-"):
        return (false, result.options, "swarmy serve: --repo requires a path\n")
      if args[i + 1].len == 0:
        return (false, result.options, "swarmy serve: --repo requires a path\n")
      result.options.repo = args[i + 1]
      i += 2
    of "--auth-token":
      if i + 1 >= args.len or args[i + 1].startsWith("-"):
        return (false, result.options, "swarmy serve: --auth-token requires a value\n")
      if args[i + 1].len == 0:
        return (false, result.options, "swarmy serve: --auth-token requires a value\n")
      result.options.authToken = args[i + 1]
      i += 2
    of "--max-body-bytes":
      if i + 1 >= args.len or args[i + 1].startsWith("-"):
        return (
          false,
          result.options,
          "swarmy serve: --max-body-bytes requires a value\n"
        )
      let parsed = parseMaxBodyBytes(args[i + 1])
      if not parsed.ok:
        return (false, result.options, parsed.error)
      result.options.maxBodyBytes = parsed.value
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
  let bindAuth = validateBindAuth(parsed.options)
  if not bindAuth.ok:
    return CliResult(exitCode: 2, error: bindAuth.error)

  CliResult(exitCode: 0, output: parsed.options.preview)

proc serveBlocking*(args: seq[string]): CliResult =
  let parsed = parseServeArgs(args)
  if not parsed.ok:
    return CliResult(exitCode: 2, error: parsed.error)
  let bindAuth = validateBindAuth(parsed.options)
  if not bindAuth.ok:
    return CliResult(exitCode: 2, error: bindAuth.error)

  let staticCheck = validateStaticDir(parsed.options.staticDir)
  if not staticCheck.ok:
    return CliResult(exitCode: 1, error: staticCheck.error)

  try:
    stdout.write(parsed.options.preview)
    stdout.flushFile()
    server_app.serve(ServerConfig(
      address: parsed.options.host,
      port: parsed.options.port,
      staticDir: parsed.options.staticDir,
      repoPath: parsed.options.repo,
      authToken: parsed.options.authToken,
      maxBodyBytes: parsed.options.maxBodyBytes
    ))
  except CatchableError as err:
    return CliResult(
      exitCode: 1,
      error: "swarmy serve: failed to start http://" & parsed.options.host &
        ":" & $parsed.options.port & ": " & err.msg & "\n"
    )
  CliResult(exitCode: 0)
