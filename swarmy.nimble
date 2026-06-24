# Package

version       = "0.1.0"
author        = "swarmy contributors"
description   = "Loops made visible"
license       = "MIT"
srcDir        = "src"
bin           = @["swarmy"]

# Dependencies

requires "nim >= 2.2.4"

# Tasks

task buildAll, "Build the Nim backend and Svelte frontend":
  exec "nimble build"
  exec "npm run build --workspace apps/web"
