import std/os

let jazzySrc = getEnv("JAZZY_SRC")
if jazzySrc.len > 0 and dirExists(jazzySrc):
  switch("path", jazzySrc)
elif dirExists("../jazzy-framework/src"):
  switch("path", "../jazzy-framework/src")
