import os, strutils

when defined(Windows):
  import strformat

import ".."/globals

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
    result = gState.nim

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

proc fixCmd*(cmd: string): string =
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
