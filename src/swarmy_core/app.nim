import std/json

const
  Name* = "swarmy"
  Version* = "0.1.0"

type
  AppInfo* = object
    name*: string
    version*: string
    mode*: string

proc appInfo*(mode = "development"): AppInfo =
  AppInfo(name: Name, version: Version, mode: mode)

proc toJson*(info: AppInfo): JsonNode =
  %*{
    "name": info.name,
    "version": info.version,
    "mode": info.mode
  }
