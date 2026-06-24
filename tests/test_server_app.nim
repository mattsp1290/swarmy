import std/[asyncdispatch, httpcore, json, os, times, unittest]

import jazzy

import swarmy_core/app
import swarmy_server/app as server_app

proc withTempDist(body: proc(dir: string)) =
  let dir = getTempDir() / "swarmy-server-test-" & $getCurrentProcessId() &
    "-" & $epochTime().int
  createDir(dir)
  createDir(dir / "assets")
  writeFile(dir / "index.html", "<!doctype html><title>Swarmy</title>")
  writeFile(dir / "assets" / "app.js", "console.log('swarmy');")
  try:
    body(dir)
  finally:
    removeDir(dir)

proc dispatchGet(path: string): Context =
  let req = JazzyRequest(
    httpMethod: HttpGet,
    path: path,
    headers: newHttpHeaders()
  )
  result = newContext(req)
  waitFor dispatch(result)

suite "server app":
  test "registers health and static app routes":
    withTempDist proc(dist: string) =
      server_app.registerRoutes(dist)

      let health = dispatchGet("/api/health")
      check health.response.code == 200
      let payload = parseJson(health.response.body)
      check payload["status"].getStr == "ok"
      check payload["name"].getStr == Name
      check payload["version"].getStr == Version

      let index = dispatchGet("/")
      check index.response.code == 200
      check "<title>Swarmy</title>" in index.response.body
      check index.response.headers["Content-Type"] == "text/html"

      let asset = dispatchGet("/assets/app.js")
      check asset.response.code == 200
      check asset.response.body == "console.log('swarmy');"
