##[
Module that imports everything so that `nim doc --project nimtero/api` runs docs
on everything.
]##

when true:
  ## pending https://github.com/nim-lang/Nim/pull/10527
  import sequtils, os, strformat, macros
  import ./paths
  macro importPaths(a: static openArray[string]): untyped =
    result = newStmtList()
    for ai in a: result.add quote do: from `ai` import nil

  const dir = nimteropSrcDir()
  const files = block:
    var ret: seq[string]
    for path in walkDirRec(dir, yieldFilter = {pcFile}):
      if path.splitFile.ext != ".nim": continue
      if path.splitFile.name in ["astold"]: continue
      if path == currentSourcePath: continue
      ret.add path
    ret
  static: echo files
  importPaths files
