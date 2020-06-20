import ".."/globals
import "."/getters

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
    doAssert false, "Bad AST " & $(idx: idx)

  if gTokens[idx] == "(":
    if gTokens.len - idx < 2:
      doAssert false, "Corrupt AST " & $(gTokensLen: gTokens.len, idx: idx)
    result = new(Ast)
    (result.name, result.kind, result.recursive) = gTokens[idx+1].getNameKind()
    result.children = @[]
    if result.recursive:
      result.children.add(result)
    idx += 2
    while gTokens[idx] != ")":
      var res = readFromTokens()
      if not res.isNil:
        result.children.add(res)
  elif gTokens[idx] == ")":
    doAssert false, "Poor AST " & $(idx: idx)

  idx += 1

proc printAst*(node: ref Ast, offset=""): string =
  result = offset & "(" & (if node.recursive: "^" else: "") & node.name & node.kind.toString()

  if node.children.nBl and not node.recursive:
    result &= "\n"
    for child in node.children:
      result &= printAst(child, offset & " ")
    result &= offset & ")\n"
  else:
    result &= ")\n"

proc parseLisp*(tree: string): ref Ast =
  tokenize(tree)

  return readFromTokens()
