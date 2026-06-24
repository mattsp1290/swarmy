import std/[json, options, os, random, strformat, times]

const
  RunMetadataSchemaVersion* = 1
  SwarmyDirName* = ".swarmy"
  MetadataFileName* = "run.json"

type
  RunMetadata* = object
    schemaVersion*: int
    runId*: string
    repoPath*: string
    createdAt*: string
    dbPath*: string

  InitResult* = object
    metadata*: RunMetadata
    metadataPath*: string
    created*: bool

proc defaultDbPath*(repoPath: string): string =
  repoPath / SwarmyDirName / "swarmy.db"

proc metadataPath*(repoPath: string): string =
  repoPath / SwarmyDirName / MetadataFileName

proc canonicalRepoPath*(repoPath: string): string =
  let absolute = absolutePath(repoPath)
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
    dbPath: dbPath.get(defaultDbPath(canonical))
  )

proc toJson*(metadata: RunMetadata): JsonNode =
  %*{
    "schema_version": metadata.schemaVersion,
    "run_id": metadata.runId,
    "repo_path": metadata.repoPath,
    "created_at": metadata.createdAt,
    "db_path": metadata.dbPath
  }

proc fromJson*(node: JsonNode): RunMetadata =
  RunMetadata(
    schemaVersion: node["schema_version"].getInt,
    runId: node["run_id"].getStr,
    repoPath: node["repo_path"].getStr,
    createdAt: node["created_at"].getStr,
    dbPath: node["db_path"].getStr
  )

proc readRunMetadata*(path: string): RunMetadata =
  fromJson(parseFile(path))

proc writeRunMetadata*(path: string, metadata: RunMetadata) =
  writeFile(path, metadata.toJson.pretty & "\n")

proc initRun*(repoPath: string, dbPath: Option[string] = none(string)): InitResult =
  let canonical = canonicalRepoPath(repoPath)
  discard ensureSafeSwarmyDir(canonical)

  let path = metadataPath(canonical)
  if fileExists(path):
    let existing = readRunMetadata(path)
    return InitResult(metadata: existing, metadataPath: path, created: false)

  let metadata = newRunMetadata(canonical, dbPath)
  writeRunMetadata(path, metadata)
  InitResult(metadata: metadata, metadataPath: path, created: true)
