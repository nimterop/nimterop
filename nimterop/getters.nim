import macros, strutils

import regex

import globals

proc getIdentifier*(str: string): string =
  result = str.strip(chars={'_'})

proc getType*(str: string): string =
  result = str.strip(chars={'_'}).replace(re"([u]?int[\d]+)_t", "$1").replace(re"^void$", "object")
  
proc getLit*(str: string): string =
  if str.contains(re"^[\-]?[\d]+$") or
    str.contains(re"^[\-]?[\d]*\.[\d]+$") or
    str.contains(re"^0x[\d]+$"):
    return str

proc getNodeValIf*(node: ref Ast, esym: string): string =
  if esym != node.sym:
    return
  
  return gCode[node.start .. node.stop-1].strip()

proc getGccPaths*(mode = "c"): string =
  let
    nul = when defined(Windows): "nul" else: "/dev/null"
  
  return staticExec("gcc -Wp,-v -x" & mode & " " & nul)

proc getLineCol*(node: ref Ast): tuple[line, col: int] =
  result.line = 1
  result.col = 1
  for i in 0 .. node.start-1:
    if gCode[i] == '\n':
      result.col = 0
      result.line += 1
    result.col += 1