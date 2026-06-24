import std/[json, os]

import jazzy

import swarmy_core/app as core_app

type ServerConfig* = object
  address*: string
  port*: int
  staticDir*: string

var staticRoot = ""

proc setStaticRoot(path: string) =
  {.cast(gcsafe).}:
    staticRoot = normalizedPath(absolutePath(path))

proc currentStaticRoot(): string =
  {.cast(gcsafe).}:
    result = staticRoot

proc health(ctx: Context) {.gcsafe.} =
  ctx.json(%*{
    "status": "ok",
    "name": core_app.Name,
    "version": core_app.Version
  })

proc appIndex(ctx: Context) {.gcsafe.} =
  let indexPath = currentStaticRoot() / "index.html"
  if not fileExists(indexPath):
    ctx.status(404).text("web app build not found: " & indexPath)
    return

  ctx.html(readFile(indexPath))

proc registerRoutes*(staticDir: string) =
  setStaticRoot(staticDir)
  Route.get("/api/health", health)
  Route.get("/", appIndex)

  let assetsDir = currentStaticRoot() / "assets"
  if dirExists(assetsDir):
    Route.staticRoute(assetsDir, "/assets")

proc serve*(config: ServerConfig) =
  registerRoutes(config.staticDir)
  Jazzy.serve(config.port, config.address)
