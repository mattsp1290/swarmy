import std/[json, options, os, posix, random, strformat, times]

const
  RunMetadataSchemaVersion* = 1
  SwarmyDirName* = ".swarmy"
  MetadataFileName* = "run.json"
  ConfigFileName* = "config.json"
  InitLockFileName* = "init.lock"

type
  RunMetadata* = object
    schemaVersion*: int
    runId*: string
    repoPath*: string
    createdAt*: string
    dbPath*: string
    configPath*: string
    dbPathTrusted*: bool

  InitResult* = object
    metadata*: RunMetadata
    metadataPath*: string
    created*: bool

proc defaultDbPath*(repoPath: string): string =
  repoPath / SwarmyDirName / "swarmy.db"

proc defaultConfigPath*(repoPath: string): string =
  repoPath / SwarmyDirName / ConfigFileName

proc metadataPath*(repoPath: string): string =
  repoPath / SwarmyDirName / MetadataFileName

proc initLockPath(repoPath: string): string =
  repoPath / SwarmyDirName / InitLockFileName

proc canonicalRepoPath*(repoPath: string): string =
  let absolute = expandFilename(absolutePath(repoPath))
  if not dirExists(absolute):
    raise newException(ValueError, "repo path does not exist: " & repoPath)
  normalizedPath(absolute)

proc ensureSafeSwarmyDir(repoPath: string): string =
  let swarmyDir = repoPath / SwarmyDirName
  if symlinkExists(swarmyDir):
    raise newException(ValueError, ".swarmy must not be a symlink: " & swarmyDir)
  if fileExists(swarmyDir):
    raise newException(ValueError, ".swarmy exists and is not a directory: " & swarmyDir)
  if not dirExists(swarmyDir):
    createDir(swarmyDir)
  swarmyDir

proc assertSafeMetadataFile(path: string) =
  if symlinkExists(path):
    raise newException(ValueError, "metadata file must not be a symlink: " & path)
  if dirExists(path):
    raise newException(ValueError, "metadata path is a directory: " & path)

proc canonicalPossiblyMissingPath(path: string): string =
  let absolute = absolutePath(path)
  var dir = parentDir(absolute)
  var missingParts: seq[string]
  while dir.len > 0 and not dirExists(dir):
    missingParts.insert(extractFilename(dir), 0)
    let nextDir = parentDir(dir)
    if nextDir == dir:
      break
    dir = nextDir

  var canonicalParent = if dir.len > 0 and dirExists(dir):
    expandFilename(dir)
  else:
    normalizedPath(dir)

  for part in missingParts:
    canonicalParent = canonicalParent / part

  normalizedPath(canonicalParent / extractFilename(absolute))

proc canonicalDbPath*(repoPath: string, dbPath: Option[string]): string =
  if dbPath.isNone:
    let canonical = defaultDbPath(repoPath)
    if symlinkExists(canonical):
      raise newException(ValueError, "db path must not be a symlink: " & canonical)
    return canonical

  let raw = dbPath.get
  let canonical = if raw.isAbsolute:
    canonicalPossiblyMissingPath(raw)
  else:
    canonicalPossiblyMissingPath(absolutePath(raw, repoPath))

  if symlinkExists(canonical):
    raise newException(ValueError, "db path must not be a symlink: " & canonical)
  canonical

proc newRunId*(): string =
  randomize()
  let now = getTime().toUnix()
  let a = rand(uint32)
  let b = rand(uint32)
  &"run-{now:x}-{a:08x}{b:08x}"

proc newRunMetadata*(repoPath: string, dbPath: Option[string] = none(string)): RunMetadata =
  let canonical = canonicalRepoPath(repoPath)
  RunMetadata(
    schemaVersion: RunMetadataSchemaVersion,
    runId: newRunId(),
    repoPath: canonical,
    createdAt: now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    dbPath: canonicalDbPath(canonical, dbPath),
    configPath: defaultConfigPath(canonical),
    dbPathTrusted: dbPath.isSome
  )

proc toJson*(metadata: RunMetadata): JsonNode =
  %*{
    "schema_version": metadata.schemaVersion,
    "run_id": metadata.runId,
    "repo_path": metadata.repoPath,
    "created_at": metadata.createdAt,
    "db_path": metadata.dbPath,
    "config_path": metadata.configPath,
    "db_path_trusted": metadata.dbPathTrusted
  }

proc fromJson*(node: JsonNode): RunMetadata =
  let repoPath = canonicalRepoPath(node["repo_path"].getStr)
  let dbPath = canonicalDbPath(repoPath, some(node["db_path"].getStr))
  let trustedExternalDb = node.hasKey("db_path_trusted") and
    node["db_path_trusted"].kind == JBool and
    node["db_path_trusted"].getBool
  if dbPath != defaultDbPath(repoPath) and not trustedExternalDb:
    raise newException(
      ValueError,
      "metadata db_path outside repo-local default requires db_path_trusted"
    )

  RunMetadata(
    schemaVersion: node["schema_version"].getInt,
    runId: node["run_id"].getStr,
    repoPath: repoPath,
    createdAt: node["created_at"].getStr,
    dbPath: dbPath,
    configPath: defaultConfigPath(repoPath),
    dbPathTrusted: trustedExternalDb
  )

proc readFileNoFollow(path: string): string =
  when defined(posix) and declared(O_NOFOLLOW):
    let fd = posix.open(path.cstring, O_RDONLY or O_NOFOLLOW)
    if fd < 0:
      raise newException(IOError, "cannot open metadata file safely: " & path)
    try:
      var buffer: array[4096, char]
      while true:
        let readBytes = posix.read(fd, addr buffer[0], buffer.len)
        if readBytes < 0:
          raise newException(IOError, "cannot read metadata file: " & path)
        if readBytes == 0:
          break
        result.add(buffer[0 ..< readBytes])
    finally:
      discard posix.close(fd)
  else:
    assertSafeMetadataFile(path)
    readFile(path)

proc readRunMetadata*(path: string): RunMetadata =
  fromJson(parseJson(readFileNoFollow(path)))

proc writeRunMetadata*(path: string, metadata: RunMetadata) =
  writeFile(path, metadata.toJson.pretty & "\n")

proc writeRunMetadataAtomically(path: string, metadata: RunMetadata) =
  let tempPath = path & ".tmp-" & newRunId()
  writeRunMetadata(tempPath, metadata)
  moveFile(tempPath, path)

proc acquireInitLock(lockPath: string): cint =
  for _ in 0 ..< 500:
    if symlinkExists(lockPath):
      raise newException(ValueError, "init lock must not be a symlink: " & lockPath)
    let fd = posix.open(lockPath.cstring, O_CREAT or O_EXCL or O_WRONLY, Mode(0o600))
    if fd >= 0:
      return fd
    if fileExists(lockPath):
      sleep(10)
    else:
      raise newException(IOError, "cannot create init lock: " & lockPath)

  raise newException(IOError, "timed out waiting for init lock: " & lockPath)

proc releaseInitLock(lockPath: string, lockFd: cint) =
  discard posix.close(lockFd)
  if fileExists(lockPath):
    removeFile(lockPath)

proc initRun*(repoPath: string, dbPath: Option[string] = none(string)): InitResult =
  let canonical = canonicalRepoPath(repoPath)
  discard ensureSafeSwarmyDir(canonical)

  let path = metadataPath(canonical)
  let lockPath = initLockPath(canonical)
  let lockFile = acquireInitLock(lockPath)
  try:
    assertSafeMetadataFile(path)
    if fileExists(path):
      let existing = readRunMetadata(path)
      return InitResult(metadata: existing, metadataPath: path, created: false)

    let metadata = newRunMetadata(canonical, dbPath)
    writeRunMetadataAtomically(path, metadata)
    InitResult(metadata: metadata, metadataPath: path, created: true)
  finally:
    releaseInitLock(lockPath, lockFile)
