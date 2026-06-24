import std/[os, unittest]

import helpers/temp_repos

suite "smoke harness helpers":
  test "temp repo helper creates isolated repo and db path":
    var seenRoot = ""
    withTempRepo proc(temp: TempRepo) =
      seenRoot = temp.root
      check dirExists(temp.root)
      check dirExists(temp.repo)
      check parentDir(temp.dbPath) == temp.root
      check extractFilename(temp.dbPath) == "swarmy.db"
      check not fileExists(temp.dbPath)

    check seenRoot.len > 0
    check not dirExists(seenRoot)
