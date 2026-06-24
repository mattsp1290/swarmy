import std/[os, strutils]

let jazzySrc = getEnv("JAZZY_SRC")
if jazzySrc.len > 0:
  if not dirExists(jazzySrc):
    quit("JAZZY_SRC does not exist: " & jazzySrc)
  switch("path", jazzySrc)
else:
  let pkgsDir = getHomeDir() / ".nimble" / "pkgs2"
  if dirExists(pkgsDir):
    for kind, path in walkDir(pkgsDir):
      if kind == pcDir and path.extractFilename.startsWith("jazzy-0.5.0-"):
        switch("path", path)
        break
