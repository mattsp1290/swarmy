# Package
import std/[os, strutils]

version       = "0.1.0"
author        = "swarmy contributors"
description   = "Loops made visible"
license       = "MIT"
srcDir        = "src"
bin           = @["swarmy"]

# Dependencies

requires "nim >= 2.2.4"
requires "https://github.com/mattsp1290/jazzy-framework#a961fd30341a27c94195ddc81184b81fea4317a5"
requires "tiny_sqlite >= 0.2.0"

# Tasks

task test, "Run Nim tests":
  for file in listFiles("tests"):
    if file.startsWith("tests" / "test_") and file.endsWith(".nim"):
      exec "nim c -r --path:src --hints:off --verbosity:0 " & file

task buildAll, "Build the Nim backend and Svelte frontend":
  exec "nimble build"
  exec "npm run build --workspace apps/web"
