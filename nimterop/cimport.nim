import macros, os, strformat, strutils

import ast, getters, globals, lisp

proc search(path: string): string =
  result = joinPath(getProjectPath(), path).replace("\\", "/")
  if not fileExists(result) and not dirExists(result):
    result = path
    if not fileExists(result) and not dirExists(result):
      var found = false
      for inc in gIncludeDirs:
        result = inc & "/" & path
        if fileExists(result) or dirExists(result):
          found = true
          break
      if not found:
        echo "File or directory not found: " & path
        quit(1)

macro cDebug*(): untyped =
  gDebug = true

macro cDefine*(name: static[string], val: static[string] = ""): untyped =
  result = newNimNode(nnkStmtList)
  
  var str = "-D" & name
  if val.nBl:
    str &= "=\"" & val & "\""
  
  result.add(quote do:
    {.passC: `str`.}
  )

  if gDebug:
    echo result.repr

macro cIncludeDir*(dir: static[string]): untyped =
  result = newNimNode(nnkStmtList)

  let fullpath = search(dir)
  gIncludeDirs.add(fullpath)
  
  let str = "-I\"" & fullpath & "\""
  result.add(quote do:
    {.passC: `str`.}
  )
  
  if gDebug:
    echo result.repr

macro cIncludeC*(): untyped =
  result = newNimNode(nnkStmtList)

  var
    inc = false
  for line in getGccPaths().splitLines():
    if "#include <...> search starts here" in line:
      inc = true
      continue
    elif "End of search list" in line:
      break
    
    if inc:
      if gDebug:
        echo "Including " & line.strip()
      gIncludeDirs.add(line.strip())

macro cCompile*(path: static[string]): untyped =
  result = newNimNode(nnkStmtList)

  var
    stmt = ""
    flags = ""

  proc fcompile(file: string): string =
    let fn = file.splitFile().name
    var
      ufn = fn
      uniq = 1
    while ufn in gCompile:
      ufn = fn & $uniq
      uniq += 1

    gCompile.add(ufn)
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
    let fpath = search(path)
    if fileExists(fpath):
      stmt &= fcompile(fpath) & "\n"
    elif dirExists(fpath):
      if flags.contains("cpp"):
        for i in @["*.C", "*.cpp", "*.c++", "*.cc", "*.cxx"]:
          dcompile(fpath / i)
      else:
        dcompile(fpath / "*.c")

  result.add stmt.parseStmt()
  
  if gDebug:
    echo result.repr

macro cImport*(filename: static[string]): untyped =
  result = newNimNode(nnkStmtList)
  result.add addReorder()

  let
    fullpath = search(filename)
    root = parseLisp(fullpath)

  echo "Importing " & fullpath
  
  gCode = staticRead(fullpath)
  gConstStr = ""
  gTypeStr = ""
  
  addHeader(fullpath)
  genNimAst(root)
  
  if gConstStr.nBl:
    if gDebug:
      echo "const\n" & gConstStr
    result.add parseStmt(
      "const\n" & gConstStr
    )

  if gTypeStr.nBl:
    if gDebug:
      echo "type\n" & gTypeStr
    result.add parseStmt(
      "type\n" & gTypeStr
    )

  if gProcStr.nBl:
    if gDebug:
      echo gProcStr
    result.add gProcStr.parseStmt()
    
  if gDebug:
    echo result.repr