import macros, os, strformat, strutils

const CIMPORT {.used.} = 1

include "."/globals

proc interpPath(dir: string): string=
  # TODO: more robust: needs a DirSep after "$projpath"
  result = dir.replace("$projpath", getProjectPath())

proc joinPathIfRel(path1: string, path2: string): string =
  if path2.isAbsolute:
    result = path2
  else:
    result = joinPath(path1, path2)

proc findPath(path: string, fail = true): string =
  # Relative to project path
  result = joinPathIfRel(getProjectPath(), path).replace("\\", "/")
  if not fileExists(result) and not dirExists(result):
    if fail:
      doAssert false, "File or directory not found: " & path
    else:
      return ""

proc walkDirImpl(indir, inext: string, file=true): seq[string] =
  let
    dir = joinPathIfRel(getProjectPath(), indir)
    ext =
      if inext.len != 0:
        when not defined(Windows):
          "-name " & inext
        else:
          "\\" & inext
      else:
        ""

  let
    cmd =
      when defined(Windows):
        if file:
          "cmd /c dir /s/b/a-d " & dir.replace("/", "\\") & ext
        else:
          "cmd /c dir /s/b/ad " & dir.replace("/", "\\")
      else:
        if file:
          "find $1 -type f $2" % [dir, ext]
        else:
          "find $1 -type d" % dir

    (output, ret) = gorgeEx(cmd)

  if ret == 0:
    result = output.splitLines()

proc getFileDate(fullpath: string): string =
  var
    ret = 0
    cmd =
      when defined(Windows):
        &"cmd /c for %a in ({fullpath.quoteShell}) do echo %~ta"
      else:
        &"stat -c %y {fullpath.quoteShell}"

  (result, ret) = gorgeEx(cmd)

  if ret != 0:
    doAssert false, "File date error: " & fullpath & "\n" & result

proc getToast(fullpath: string, recurse: bool = false): string =
  var
    cmd = when defined(Windows): "cmd /c " else: ""

  cmd &= "toast --pnim --preprocess "

  if recurse:
    cmd.add "--recurse "

  for i in gStateCT.defines:
    cmd.add &"--defines+={i.quoteShell} "

  for i in gStateCT.includeDirs:
    cmd.add &"--includeDirs+={i.quoteShell} "

  cmd.add &"{fullpath.quoteShell}"
  echo cmd
  var (output, exitCode) = gorgeEx(cmd, cache=getFileDate(fullpath))
  doAssert exitCode == 0, $exitCode
  result = output

proc getGccPaths*(mode = "c"): string =
  var
    ret = 0
    nul = when defined(Windows): "nul" else: "/dev/null"
    mmode = if mode == "cpp": "c++" else: mode

  (result, ret) = gorgeEx("gcc -Wp,-v -x" & mmode & " " & nul)

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

macro cCompile*(path: static string, mode = "c"): untyped =
  result = newNimNode(nnkStmtList)

  var
    stmt = ""

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

  proc dcompile(dir: string, ext=""): string =
    let
      files = walkDirImpl(dir, ext)

    for f in files:
      if f.len != 0:
        result &= fcompile(f) & "\n"

  if path.contains("*") or path.contains("?"):
    stmt &= dcompile(path)
  else:
    let fpath = findPath(path)
    if fileExists(fpath):
      stmt &= fcompile(fpath) & "\n"
    elif dirExists(fpath):
      if mode.strVal().contains("cpp"):
        for i in @["*.C", "*.cpp", "*.c++", "*.cc", "*.cxx"]:
          stmt &= dcompile(fpath, i)
      else:
        stmt &= dcompile(fpath, "*.c")

  result.add stmt.parseStmt()

  if gStateCT.debug:
    echo result.repr

macro cImport*(filename: static string, recurse: static bool = false): untyped =
  result = newNimNode(nnkStmtList)

  let
    fullpath = findPath(filename)

  echo "Importing " & fullpath

  let
    output = getToast(fullpath, recurse)

  try:
    result.add parseStmt(output)
  except:
    echo output
    echo "Failed to import generated nim"
    result.add parseStmt(output)

  if gStateCT.debug:
    echo result.repr
