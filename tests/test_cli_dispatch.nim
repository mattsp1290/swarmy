import std/[strutils, unittest]

import swarmy_cli/dispatch
import swarmy_core/app

suite "cli dispatch":
  test "version comes from core app metadata":
    let result = run(@["--version"])

    check result.exitCode == 0
    check result.output == Name & " " & Version & "\n"
    check result.error == ""

  test "serve dispatches through the internal serve module":
    let result = run(@["serve"])

    check result.exitCode == 0
    check result.output == "swarmy serve: server seam ready\n"
    check result.error == ""

  test "init validates arguments before reaching metadata writes":
    let result = run(@["init", "--repo"])

    check result.exitCode == 2
    check result.output == ""
    check "--repo requires a path" in result.error

  test "mcp dispatches through the internal mcp module":
    let result = run(@["mcp"])

    check result.exitCode == 0
    check result.output == "swarmy mcp: MCP server seam ready\n"
    check result.error == ""

  test "unknown commands fail before reaching a module":
    let result = run(@["unknown"])

    check result.exitCode == 2
    check result.output == ""
    check "unknown command" in result.error
