import std/[json, os]

type
  AppInfo* = object
    name*: string
    version*: string
    mode*: string

proc appInfo*(mode = "development"): AppInfo =
  AppInfo(name: "swarmy", version: "0.1.0", mode: mode)

proc toJson*(info: AppInfo): JsonNode =
  %*{
    "name": info.name,
    "version": info.version,
    "mode": info.mode
  }

proc main() =
  let mode = getEnv("SWARMY_MODE", "development")
  echo appInfo(mode).toJson()

when isMainModule:
  main()

