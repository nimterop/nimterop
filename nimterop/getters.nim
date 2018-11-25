import macros, strformat, strutils

import regex

import git, globals

proc getIdentifier*(str: string): string =
  result = str.strip(chars={'_'})

proc getType*(str: string): string =
  result = str.strip(chars={'_'}).replace(re"([u]?int[\d]+)_t", "$1").replace(re"^void$", "object")

proc getLit*(str: string): string =
  if str.contains(re"^[\-]?[\d]+$") or
    str.contains(re"^[\-]?[\d]*\.[\d]+$") or
    str.contains(re"^0x[\d]+$"):
    return str

proc getNodeValIf*(node: ref Ast, esym: Sym): string =
  if esym != node.sym:
    return

  return gCode[node.start .. node.stop-1].strip()

proc getLineCol*(node: ref Ast): tuple[line, col: int] =
  result.line = 1
  result.col = 1
  for i in 0 .. node.start-1:
    if gCode[i] == '\n':
      result.col = 0
      result.line += 1
    result.col += 1

proc getGccPaths*(mode = "c"): string =
  var
    nul = when defined(Windows): "nul" else: "/dev/null"
    mmode = if mode == "cpp": "c++" else: mode

  return staticExec("gcc -Wp,-v -x" & mmode & " " & nul)

proc getPreprocessor*(fullpath: string, mode = "cpp"): string =
  var
    mmode = if mode == "cpp": "c++" else: mode
    cmd = &"gcc -E -dD -x{mmode} "

  for inc in gIncludeDirs:
    cmd &= &"-I\"{inc}\" "

  for def in gDefines:
    cmd &= &"-D{def} "

  cmd &= &"\"{fullpath}\""
  return staticExec(cmd)