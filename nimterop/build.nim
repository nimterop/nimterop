import hashes, macros, osproc, sets, strformat, strutils, tables

import os except findExe, sleep

export extractFilename, `/`

# build specific debug since we cannot import globals (yet)
var
  gDebug* = false
  gDebugCT* {.compileTime.} = false
  gNimExe* = ""

# Misc helpers
proc echoDebug(str: string) =
  let str = "\n# " & str.strip().replace("\n", "\n# ")
  when nimvm:
    if gDebugCT: echo str
  else:
    if gDebug: echo str

proc sanitizePath*(path: string, noQuote = false, sep = $DirSep): string =
  result = path.multiReplace([("\\\\", sep), ("\\", sep), ("/", sep)])
  if not noQuote:
    result = result.quoteShell

proc getCurrentNimCompiler*(): string =
  when nimvm:
    result = getCurrentCompilerExe()
    when defined(nimsuggest):
      result = result.replace("nimsuggest", "nim")
  else:
    result = gNimExe

template fixOutDir() {.dirty.} =
  let
    outdir = if outdir.isAbsolute(): outdir else: getProjectDir() / outdir

proc compareVersions*(ver1, ver2: string): int =
  ## Compare two version strings x.y.z and return -1, 0, 1
  ##
  ## ver1 < ver2 = -1
  ## ver1 = ver2 = 0
  ## ver1 > ver2 = 1
  let
    ver1seq = ver1.replace("-", "").split('.')
    ver2seq = ver2.replace("-", "").split('.')
  for i in 0 ..< ver1seq.len:
    let
      p1 = ver1seq[i]
      p2 = if i < ver2seq.len: ver2seq[i] else: "0"

    try:
      let
        h1 = p1.parseHexInt()
        h2 = p2.parseHexInt()

      if h1 < h2: return -1
      elif h1 > h2: return 1
    except ValueError:
      if p1 < p2: return -1
      elif p1 > p2: return 1

proc fixCmd(cmd: string): string =
  when defined(Windows):
    # Replace 'cd d:\abc' with 'd: && cd d:\abc`
    var filteredCmd = cmd
    if cmd.toLower().startsWith("cd"):
      var
        colonIndex = cmd.find(":")
        driveLetter = cmd.substr(colonIndex-1, colonIndex)
      if (driveLetter[0].isAlphaAscii() and
          driveLetter[1] == ':' and
          colonIndex == 4):
        filteredCmd = &"{driveLetter} && {cmd}"
    result = "cmd /c " & filteredCmd
  elif defined(posix):
    result = cmd
  else:
    doAssert false

# Nim cfg file related functionality
include "."/build/nimconf

proc getNimteropCacheDir(): string =
  # Get location to cache all nimterop artifacts
  result = getNimcacheDir() / "nimterop"

# Functionality shelled out to external executables
include "."/build/shell

proc getProjectCacheDir*(name: string, forceClean = true): string =
  ## Get a cache directory where all nimterop artifacts can be stored
  ##
  ## Projects can use this location to download source code and build binaries
  ## that can be then accessed by multiple apps. This is created under the
  ## per-user Nim cache directory.
  ##
  ## Use `name` to specify the subdirectory name for a project.
  ##
  ## `forceClean` is enabled by default and effectively deletes the folder
  ## if Nim is compiled with the `-f` or `--forceBuild` flag. This allows
  ## any project to start out with a clean cache dir on a forced build.
  ##
  ## NOTE: avoid calling `getProjectCacheDir()` multiple times on the same
  ## `name` when `forceClean = true` else checked out source might get deleted
  ## at the wrong time during build.
  ##
  ## E.g.
  ##   `nimgit2` downloads `libgit2` source so `name = "libgit2"`
  ##
  ##   `nimarchive` downloads `libarchive`, `bzlib`, `liblzma` and `zlib` so
  ##   `name = "nimarchive" / "libarchive"` for `libarchive`, etc.
  result = getNimteropCacheDir() / name

  if forceClean and compileOption("forceBuild"):
    echo "# Removing " & result
    rmDir(result)

# C compiler support
include "."/build/ccompiler

when not defined(TOAST):
  # configure, cmake, make support
  include "."/build/tools

  # Conan.io support
  include "."/build/conan

  # Julia BinaryBuilder.org support
  include "."/build/jbb

  # getHeader support
  include "."/build/getheader
