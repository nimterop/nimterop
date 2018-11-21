import strutils

import regex

import globals

var
  gTokens {.compiletime.}: seq[string]
  idx {.compiletime.} = 0

proc tokenize(fullpath: string) =
  var collect = ""
  
  gTokens = @[]
  idx = 0
  for i in staticExec("toast -u " & fullpath):
    case i:
      of ' ', '\n', '\r', '(', ')':
        if collect.nBl:
          gTokens.add(collect)
          collect = ""
        if i in ['(', ')']:
          gTokens.add($i)
      else:
        collect &= $i

  if gTokens.len() == 0:
    echo "toast binary not installed - nimble install nimterop to force build"
    quit(1)

proc readFromTokens(): ref Ast =
  if idx == gTokens.len():
    echo "Bad AST"
    quit(1)

  if gTokens[idx] == "(":
    if gTokens.len() - idx < 2:
      echo "Corrupt AST"
      quit(1)
    if gTokens[idx+1] != "comment":
      result = new(Ast)
      try:
        result.sym = parseEnum[Sym](gTokens[idx+1])
      except:
        result.sym = IGNORED
      result.start = gTokens[idx+2].parseInt().uint32
      result.stop = gTokens[idx+3].parseInt().uint32
      result.children = @[]
    idx += 4
    while gTokens[idx] != ")":
      var res = readFromTokens()
      if not res.isNil():
        res.parent = result
        result.children.add(res)
  elif gTokens[idx] == ")":
    echo "Poor AST"
    quit(1)
  
  idx += 1

proc printAst*(node: ref Ast, offset=""): string =
  result = offset & "(" & $node.sym & " " & $node.start & " " & $node.stop
  if node.children.len() != 0:
    result &= "\n"
    for child in node.children:
      result &= printAst(child, offset & " ")
    result &= offset & ")\n"
  else:
    result &= ")\n"

proc parseLisp*(fullpath: string): ref Ast =
  tokenize(fullpath)
        
  return readFromTokens()
