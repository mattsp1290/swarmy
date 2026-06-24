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

proc canonicalDbPath(repoPath: string, dbPath: Option[string]): string =
  if dbPath.isNone:
    return defaultDbPath(repoPath)

  let raw = dbPath.get
  if raw.isAbsolute:
    normalizedPath(raw)
  else:
    normalizedPath(absolutePath(raw, repoPath))

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
    configPath: defaultConfigPath(canonical)
  )

proc toJson*(metadata: RunMetadata): JsonNode =
  %*{
    "schema_version": metadata.schemaVersion,
    "run_id": metadata.runId,
    "repo_path": metadata.repoPath,
    "created_at": metadata.createdAt,
    "db_path": metadata.dbPath,
    "config_path": metadata.configPath
  }

proc fromJson*(node: JsonNode): RunMetadata =
  RunMetadata(
    schemaVersion: node["schema_version"].getInt,
    runId: node["run_id"].getStr,
    repoPath: node["repo_path"].getStr,
    createdAt: node["created_at"].getStr,
    dbPath: node["db_path"].getStr,
    configPath: node["config_path"].getStr
  )

proc readRunMetadata*(path: string): RunMetadata =
  fromJson(parseFile(path))

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
