import strutils
import strformat

import "."/[getters, globals]

var
  gTokens: seq[string]
  idx = 0

proc tokenize(tree: string) =
  var collect = ""

  gTokens = @[]
  idx = 0
  for i in tree:
    case i:
      of ' ', '\n', '\r', '(', ')':
        if collect.nBl:
          gTokens.add(collect)
          collect = ""
        if i in ['(', ')']:
          gTokens.add($i)
      else:
        collect &= $i

proc readFromTokens(): ref Ast =
  if idx == gTokens.len:
    echo "Bad AST"
    quit(1)

  if gTokens[idx] == "(":
    if gTokens.len - idx < 2:
      echo "Corrupt AST"
      quit(1)
    if gTokens[idx+1] != "comment":
      result = new(Ast)
      (result.name, result.kind) = gTokens[idx+1].getNameKind()
      result.children = @[]
    idx += 2
    while gTokens[idx] != ")":
      var res = readFromTokens()
      if not res.isNil():
        result.children.add(res)
  elif gTokens[idx] == ")":
    echo "Poor AST"
    quit(1)

  idx += 1

proc printAst*(node: ref Ast, offset=""): string =
  result = offset & "(" & node.name & node.kind.toString()

  if node.children.len != 0:
    result &= "\n"
    for child in node.children:
      result &= printAst(child, offset & " ")
    result &= offset & ")\n"
  else:
    result &= ")\n"

proc parseLisp*(tree: string): ref Ast =
  tokenize(tree)

  return readFromTokens()
