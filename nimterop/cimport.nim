import macros, os, strformat, strutils
import "." / [globals, getters, utils]

proc interpPath(dir: string): string=
  # TODO: more robust: needs a DirSep after "$projpath"
  result = dir.replace("$projpath", getProjectPath())

proc joinPathIfRel(path1: string, path2: string): string =
  if path2.isAbsolute:
    result = path2
  else:
    result = joinPath(path1, path2)

proc findPath(path: string, fail = true): string =
  # As is
  result = path.replace("\\", "/")
  if not fileExists(result) and not dirExists(result):
    # Relative to project path
    result = joinPathIfRel(getProjectPath(), path).replace("\\", "/")
    if not fileExists(result) and not dirExists(result):
      if fail:
        doAssert false, "File or directory not found: " & path
      else:
        return ""

proc getToast(fullpath: string): string =
  # Note: this ran into: https://github.com/OpenSystemsLab/tempfile.nim/issues/9
  # import tempfile
  # let nimout = mktemp(prefix="nimterop.gen.", suffix=".nim")
  let randstr = "D20181129T165842" # TODO: actual random; and make sure doesn't exist (at CT)
  let nimout = getTempDir().joinPath(fmt"nimterop_{randstr}.nim")
  if existsFileStatic(nimout):
    removeFileStatic nimout

  var
    cmd = fmt"toast --nimout:{nimout.quoteShell} --preprocess "

  for i in gStateCT.defines:
    cmd.add &"--defines+={i.quoteShell} "

  for i in gStateCT.includeDirs:
    cmd.add &"--includeDirs+={i.quoteShell} "

  cmd.add &"--source:{fullpath.quoteShell}"
  echo cmd

  var output = execAction(cmd)
  echo output
  result = staticRead nimout
  if not gStateCT.keepNimout:
    removeFileStatic nimout

proc cSearchPath*(path: string): string {.compileTime.}=
  result = findPath(path, fail = false)
  if result.len == 0:
    var found = false
    for inc in gStateCT.searchDirs:
      result = (inc & "/" & path).replace("\\", "/")
      if fileExists(result) or dirExists(result):
        found = true
        break
    doAssert found, "File or directory not found: " & path & " gStateCT.searchDirs: " & $gStateCT.searchDirs

macro cDebug*(): untyped =
  gStateCT.debug = true

macro cDefine*(name: static string, val: static string = ""): untyped =
  result = newNimNode(nnkStmtList)

  var str = name
  if val.nBl:
    str &= &"=\"{val}\""

  if str notin gStateCT.defines:
    gStateCT.defines.add(str)
    str = "-D" & str

    result.add(quote do:
      {.passC: `str`.}
    )

    if gStateCT.debug:
      echo result.repr

macro cAddSearchDir*(dir: static string): untyped =
  var dir = interpPath(dir)
  if dir notin gStateCT.searchDirs:
    gStateCT.searchDirs.add(dir)

macro cIncludeDir*(dir: static string): untyped =
  var dir = interpPath(dir)
  result = newNimNode(nnkStmtList)

  let
    fullpath = findPath(dir)
    str = &"-I\"{fullpath}\""

  if fullpath notin gStateCT.includeDirs:
    gStateCT.includeDirs.add(fullpath)

    result.add(quote do:
      {.passC: `str`.}
    )

  if gStateCT.debug:
    echo result.repr

macro cAddStdDir*(mode = "c"): untyped =
  result = newNimNode(nnkStmtList)

  var
    inc = false

  for line in getGccPaths(mode.strVal()).splitLines():
    if "#include <...> search starts here" in line:
      inc = true
      continue
    elif "End of search list" in line:
      break

    if inc:
      let sline = line.strip()
      result.add quote do:
        cAddSearchDir(`sline`)

macro cCompile*(path: static string): untyped =
  result = newNimNode(nnkStmtList)

  var
    stmt = ""
    flags = ""

  proc fcompile(file: string): string =
    let fn = file.splitFile().name
    var
      ufn = fn
      uniq = 1
    while ufn in gStateCT.compile:
      ufn = fn & $uniq
      uniq += 1

    gStateCT.compile.add(ufn)
    if fn == ufn:
      return "{.compile: \"$#\".}" % file.replace("\\", "/")
    else:
      return "{.compile: (\"../$#\", \"$#.o\").}" % [file.replace("\\", "/"), ufn]

  proc dcompile(dir: string) =
    for f in walkFiles(dir):
      stmt &= fcompile(f) & "\n"

  if path.contains("*") or path.contains("?"):
    dcompile(path)
  else:
    let fpath = findPath(path)
    if fileExists(fpath):
      stmt &= fcompile(fpath) & "\n"
    elif dirExists(fpath):
      if flags.contains("cpp"):
        for i in @["*.C", "*.cpp", "*.c++", "*.cc", "*.cxx"]:
          dcompile(fpath / i)
      else:
        dcompile(fpath / "*.c")

  result.add stmt.parseStmt()

  if gStateCT.debug:
    echo result.repr

macro cImport*(filename: static string): untyped =
  result = newNimNode(nnkStmtList)

  let
    fullpath = findPath(filename)

  echo "Importing " & fullpath

  result.add parseStmt(getToast(fullpath))

  if gStateCT.debug:
    echo result.repr
