import json, macros, os, osproc, sets, strformat, strutils

when nimvm:
  when (NimMajor, NimMinor, NimPatch) >= (1, 2, 0):
    import std/compilesettings
else:
  discard

# Config detected with std/compilesettings or `nim dump`
type
  Config* = ref object
    NimMajor*: int
    NimMinor*: int
    NimPatch*: int

    paths*: OrderedSet[string]
    nimblePaths*: OrderedSet[string]
    nimcacheDir*: string

proc getJson(projectDir: string): JsonNode =
  # Get `nim dump` json value for `projectDir`
  var
    cmd = "nim --hints:off --dump.format:json dump dummy"
    dump = ""
    ret = 0

  if projectDir.len != 0:
    # Run `nim dump` in `projectDir` if specified
    cmd = &"cd {projectDir.sanitizePath} && " & cmd

  cmd = fixCmd(cmd)
  when nimvm:
    (dump, ret) = gorgeEx(cmd)
  else:
    (dump, ret) = execCmdEx(cmd)

  try:
    result = parseJson(dump)
  except JsonParsingError as e:
    echo "# Failed to parse `nim dump` output: " & e.msg

proc getOsCacheDir(): string =
  # OS default cache directory
  when defined(posix):
    result = getEnv("XDG_CACHE_HOME", getHomeDir() / ".cache") / "nim"
  else:
    result = getHomeDir() / "nimcache"

proc getProjectDir*(): string =
  ## Get project directory for this compilation - returns `""` at runtime
  when nimvm:
    when (NimMajor, NimMinor, NimPatch) >= (1, 2, 0):
      # If nim v1.2.0+, get from `std/compilesettings`
      result = querySetting(projectFull).parentDir()
    else:
      # Get from `macros`
      result = getProjectPath()
  else:
    discard

proc getNimcacheDir*(projectDir = ""): string =
  ## Get nimcache directory for current compilation or specified `projectDir`
  when nimvm:
    when (NimMajor, NimMinor, NimPatch) >= (1, 2, 0):
      # Get value at compile time from `std/compilesettings`
      result = querySetting(SingleValueSetting.nimcacheDir)
  else:
    discard

  # Not Nim v1.2.0+ or runtime
  if result.len == 0:
    let
      # Get project directory for < v1.2.0 at compile time
      projectDir = if projectDir.len != 0: projectDir else: getProjectDir()

    # Use `nim dump` to figure out nimcache for `projectDir`
    let
      dumpJson = getJson(projectDir)

    if dumpJson != nil and dumpJson.hasKey("nimcache"):
      result = dumpJson["nimcache"].getStr()
      let
        (head, tail) = result.splitPath()
      if "dummy" in tail:
        # Remove `dummy_d` subdir when default nimcache
        result = head

  # Set to OS defaults if not detectable
  if result.len == 0:
    result = getOsCacheDir()

proc jsonToSeq(node: JsonNode, key: string): seq[string] =
  # Convert JsonArray to seq[string] for specified `key`
  if node.hasKey(key):
    for elem in node[key].getElems():
      result.add elem.getStr()

proc getNimConfig*(projectDir = ""): Config =
  # Get `paths` - list of paths to be forwarded to Nim
  result = new(Config)
  var
    libPath, version: string
    lazyPaths, searchPaths: seq[string]

  when nimvm:
    result.NimMajor = NimMajor
    result.NimMinor = NimMinor
    result.NimPatch = NimPatch

    when (NimMajor, NimMinor, NimPatch) >= (1, 2, 0):
      # Get value at compile time from `std/compilesettings`
      libPath = getCurrentCompilerExe().parentDir().parentDir() / "lib"
      lazyPaths = querySettingSeq(MultipleValueSetting.lazyPaths)
      searchPaths = querySettingSeq(MultipleValueSetting.searchPaths)
      result.nimcacheDir = querySetting(SingleValueSetting.nimcacheDir)
  else:
    discard

  let
    # Get project directory for < v1.2.0 at compile time
    projectDir = if projectDir.len != 0: projectDir else: getProjectDir()

  # Not Nim v1.2.0+ or runtime
  if libPath.len == 0:
    let
      dumpJson = getJson(projectDir)

    if dumpJson != nil:
      if dumpJson.hasKey("version"):
        version = dumpJson["version"].getStr()
      lazyPaths = jsonToSeq(dumpJson, "lazyPaths")
      searchPaths = jsonToSeq(dumpJson, "lib_paths")
      if dumpJson.hasKey("libpath"):
        libPath = dumpJson["libpath"].getStr()
      elif searchPaths.len != 0:
        # Usually `libPath` is last entry in `searchPaths`
        libPath = searchPaths[^1]

  # Parse version
  if version.len != 0:
    let
      splversion = version.split({'.'}, maxsplit = 3)
    result.NimMajor = splversion[0].parseInt()
    result.NimMinor = splversion[1].parseInt()
    result.NimPatch = splversion[2].parseInt()

  # Find non standard lib paths added to `searchPath`
  for path in searchPaths:
    if libPath notin path:
      result.paths.incl path

  # Find `nimblePaths` in `lazyPaths`
  for path in lazyPaths:
    let
      (_, tail) = path.strip(leading = false, chars = {'/', '\\'}).splitPath()
    if tail == "pkgs":
      # Nimble path probably
      result.nimblePaths.incl path

  # Find `paths` in `lazyPaths` that aren't within `nimblePaths`
  # Have to do this separately since `nimblePaths` could be after
  # packages in `lazyPaths`
  for path in lazyPaths:
    var skip = false
    for npath in result.nimblePaths:
      if npath in path:
        skip = true
        break
    if not skip:
      result.paths.incl path

  result.nimcacheDir = getNimcacheDir(projectDir)

proc getNimConfigFlags(cfg: Config): string =
  # Convert configuration into Nim flags for cfg file or command line
  result = &"--nimcache:\"{cfg.nimcacheDir}\"\n"

  if (cfg.NimMajor, cfg.NimMinor, cfg.NimPatch) >= (1, 2, 0):
    # --clearNimbleCache if Nim v1.2.0+
    result &= "--clearNimblePath\n"

  # Add `nimblePaths` if detected - v1.2.0+
  for path in cfg.nimblePaths:
    result &= &"--nimblePath:\"{path}\"\n"

  # Add `paths` in all cases if any detected
  for path in cfg.paths:
    result &= &"--path:\"{path}\"\n"

  when defined(windows):
    result = result.replace("\\", "/")

proc getNimConfigFlags*(projectDir = ""): string =
  ## Get Nim command line configuration flags for `projectDir`
  ##
  ## If `projectDir` is not specified, it is detected if compile time or
  ## current directory is used.
  let
    cfg = getNimConfig(projectDir)
    cfgOut = getNimConfigFlags(cfg)
  return cfgOut.replace("\n", " ")

proc writeNimConfig*(cfgFile: string, projectDir = "") =
  ## Write Nim configuration for `projectDir` to specified `cfgFile`
  ##
  ## If `projectDir` is not specified, it is detected if compile time or
  ## current directory is used.
  let
    cfg = getNimConfig(projectDir)
    cfgOut = getNimConfigFlags(cfg)
  writeFile(cfgFile, cfgOut)